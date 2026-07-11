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

    ///////////////////////////////STATE VARIABLES////////////////////

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% Overcollateralized.
    uint256 private constant LIQUIDATION_PRECISION = 100; // 50/100 = 50% liquidation threshold.
    uint256 private constant PRECISION = 1e18; // 18 decimals for precision.
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; // Token address to price feed address.
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // User address to token address to amount of collateral deposited.
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted; // User address to amount of DSC minted.
    address[] private s_CollateralTokens; // Array of collateral tokens.

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////////////////EVENTS/////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

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

    ////////////////////EXTERNAL FUNCTIONS////////////////////

    function depositCollateralAndMintDsc() external {}

    /*
    @notice - Follow CEI pattern. (Checks, Effects, Interactions)
    @param tokenCollateralAddress - The address of the token that will be used as collateral. (WETH, WBTC)
    @param amountCollateral - The amount of collateral that will be deposited.
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
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

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /*
    @notice - Follow CEI pattern. (Checks, Effects, Interactions)
    @param amountDscToMint - The amount of DSC that will be minted.
    @notice - They Should have more collateral than the minimum threshold.
    */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // If they minted more than the collateral value, revert.
        _revertHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthfactor() external view {}

    //////////////////PRIVATE & INTERNAL VIEW FUNCTIONS///////////////////   (For better understanding We can start internal functions with _).

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

    //////////////////PUBLIC & EXTERNAL VIEW FUNCTIONS///////////////////

    /*
     * loop through each collateral token and get the amount they've deposited.
     * Map it to the price feed and get the value in USD.
     */

    function getAccountCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_CollateralTokens.length; i++) {
            address token = s_CollateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // Chainlink price feeds have 8 decimals, so we need to adjust for that.
        return (uint256(price) * amount) / 1e8;
    }
}
