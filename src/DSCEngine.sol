// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin.

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
    @Title : DSC Engine
    @Author : Shimul Sharma

    * This system is designed to maintain the value of 1 DecentralizedStableCoin = 1 USD.
    * The stable coin has properties like-
    * Exogenous collateral.
    * Dollar pegged.
    * Algorithmically stable.
    *
    * This system will always be overcollateralized. The value of the collateral will never be <= value of all the DSC.
    *
    * This system is similar to DAI if DAI has no governance, no fees and was only backed by WETH and WBTC.
    *
    * @Notice : This contract is the Engine of our Stablecoin system. It will be responsible for minting and burning the stable coin, as well as managing the collateral (Depositing and Withdrawing) and ensuring the stability of the system.
*/

contract DSCEngine is ReentrancyGuard {
    ///////////////////////ERRORS/////////////////////////////

    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ///////////////////////////////STATE VARIABLES////////////////////

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% Overcollateralized.
    uint256 private constant LIQUIDATION_PRECISION = 100; // 50/100 = 50% liquidation threshold.
    uint256 private constant PRECISION = 1e18; // 18 decimals for precision.
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    mapping(address token => address priceFeed) private s_priceFeeds; // Token address to price feed address.
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // User address to token address to amount of collateral deposited.
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted; // User address to amount of DSC minted.
    address[] private s_CollateralTokens; // Array of collateral tokens.

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////////////////EVENTS/////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event DscBurned(address indexed user, uint256 amountDscBurned);

    ///////////////////////MODIFIERS//////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////////////FUNCTIONS//////////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
        }

        // Loop through the token addresses and price feed  addresses and add them to the mapping.
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_CollateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////EXTERNAL/PUBLIC FUNCTIONS////////////////////

    /*
     *  @param tokenCollateralAddress - The address of the token that will be used as collateral. (WETH, WBTC)
     *  @param amountCollateral - The amount of collateral that will be deposited.
     *  @param amountDscToMint - The amount of DSC that will be minted.
     *  @notice - This function combines the depositCollateral and mintDsc functions.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
    @notice - Follow CEI pattern. (Checks, Effects, Interactions)
    @param tokenCollateralAddress - The address of the token that will be used as collateral. (WETH, WBTC)
    @param amountCollateral - The amount of collateral that will be deposited.
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        // Transfer the collateral from the user to the contract.
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
    @notice - This function combines the redeemCollateral and burnDsc functions.
    @param tokenCollateraladdress - The address of the token that will be used as collateral. (WETH, WBTC)
    @param amountCollateraltoRedeem - The amount of collateral that will be redeemed.
    @param amountDscToBurn - The amount of DSC that will be burned.
    @notice - RedeemCollateral already checks the health factor.
    */
    function redeemCollateralForDsc(
        address tokenCollateraladdress,
        uint256 amountCollateraltoRedeem,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateraladdress, amountCollateraltoRedeem);
        // RedeemCollateral already checks the health factor.
    }

    /*
    1. Check health factor is above 1 after collateral is redeemed.
    2. DRY - Don't repear yourself.
    */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    /*
    @notice - Follow CEI pattern. (Checks, Effects, Interactions)
    @param amountDscToMint - The amount of DSC that will be minted.
    @notice - They Should have more collateral than the minimum threshold.
    */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // If they minted more than the collateral value, revert.
        _revertHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) nonReentrant {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // 1.Check Health factor of the user.(Do they have enough collateral?)
        uint256 StartingHealthFactor = _healthFactor(user);
        if (StartingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        /*
         2.We burn their DSC tokens (debt) and take their collateral.
         * User that is being liquidated : $140 ETH, $100 DSC
         * debtToCover = $100. And 10% LIQUIDATION_BONUS
         * $100 DSC = ?? ETH. ---> 0.05
         * That means we're giving $110 of WETH for 100 DSC.
        */
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / PRECISION;

        uint256 totalCollateralToRedeem = (tokenAmountFromDebtCovered + bonusCollateral);

        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);

        _burnDsc(debtToCover, user, msg.sender);

        uint256 EndingEndFactor = _healthFactor(user);
        if (EndingEndFactor <= StartingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertHealthFactorIsBroken(msg.sender);
    }

    function getHealthfactor() external view {}

    //////////////////PRIVATE & INTERNAL VIEW FUNCTIONS///////////////////   (For better understanding We can start internal functions with _).

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        _revertHealthFactorIsBroken(msg.sender);
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalCollateralValueInUSD, uint256 totalDSCMinted)
    {
        totalDSCMinted = s_DSCMinted[user];
        totalCollateralValueInUSD = getAccountCollateralValueInUSD(user);
    }

    /*
     * 1.Returns how close the user is to being liquidated.
     * 2.If the health factor is below 1, they can be liquidated.
     */
    function _healthFactor(address user) private view returns (uint256) {
        // 1. Calculate the health factor using the formula: (total value of collateral) / (total value of DSC minted).
        // 2. Return the health factor.
        (uint256 totalCollateralValueInUSD, uint256 totalDSCMinted) = _getAccountInformation(user);
        uint256 CollateralAdjustedForThreshold =
            (totalCollateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (CollateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    /*
        1. Check the Health factor of the user.(Do they have enough collateral?)
        2. revert if they don't.
    */
    function _revertHealthFactorIsBroken(address user) internal view {
        uint256 UserhealthFactor = _healthFactor(user);
        if (UserhealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(UserhealthFactor);
        }
    }

    //////////////////PUBLIC & EXTERNAL VIEW FUNCTIONS (GETTER)///////////////////

    /*
     * loop through each collateral token and get the amount they've deposited.
     * Map it to the price feed and get the value in USD.
     */

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_CollateralTokens.length; i++) {
            address token = s_CollateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getTokenAmountFromUsd(address token, uint256 UsdamountinWei) public view returns (uint256) {
        // we're finding how much worth tokens are in Wei.
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // Chainlink price feeds have 8 decimals, so we need to adjust for that.
        return (UsdamountinWei * 1e8) / uint256(price);
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // Chainlink price feeds have 8 decimals, so we need to adjust for that.
        return (uint256(price) * amount) / 1e8;
    }

    function GetAccountInformation(address User)
        external
        view
        returns (uint256 totalCollateralValueInUSD, uint256 totalDSCMinted)
    {
        (totalCollateralValueInUSD, totalDSCMinted) = _getAccountInformation(User);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_CollateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
