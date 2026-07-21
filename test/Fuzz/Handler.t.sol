// SPDX-License-Identifier: MIT
/*
    - Handler is going to narrow down the way we call functions.
    - Means :- 1. Don't call redeem collateral, unless there is any amount to redeem.
*/

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../Mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine Engine;
    DecentralizedStableCoin DSC;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesMintIsCalled;

    address[] public UsersWhichHaveDepositedTheCollateral;

    MockV3Aggregator public EthUSDPriceFeed;

    constructor(DSCEngine _Engine, DecentralizedStableCoin _DSC) {
        Engine = _Engine;
        DSC = _DSC;

        address[] memory CollateralToken = Engine.getCollateralTokens();
        weth = ERC20Mock(CollateralToken[0]);
        wbtc = ERC20Mock(CollateralToken[1]);

        EthUSDPriceFeed = MockV3Aggregator(Engine.getCollateralTokenPriceFeed(address(weth)));
    }

    // Deposit Collateral Flowchart:-

    function depositCollateral(uint256 CollateralSeed, uint256 amountCollateral) public {
        ERC20Mock Collateral = _getCollateralFromSeed(CollateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);

        Collateral.mint(msg.sender, amountCollateral);

        Collateral.approve(address(Engine), amountCollateral);

        Engine.depositCollateral(address(Collateral), amountCollateral);
        vm.stopPrank();

        UsersWhichHaveDepositedTheCollateral.push(msg.sender);
    }

    // MintDSC will only be called when a user has already deposited some collateral in the protocol. Otherwise it won't get called.
    // Because invariant will be called with tons of random addresses, but most of them will not have deposited the Collateral. That's why MintDSC won't get Called.

    function mintDSC(uint256 Amount, uint256 addressSeed) public {
        if (UsersWhichHaveDepositedTheCollateral.length == 0) {
            return;
        }
        address Sender = UsersWhichHaveDepositedTheCollateral[addressSeed % UsersWhichHaveDepositedTheCollateral.length];
        (uint256 totalCollateralValueInUSD, uint256 totalDSCMinted) = Engine.GetAccountInformation(Sender);
        int256 maxDscToMint = (int256(totalCollateralValueInUSD) / 2) - int256(totalDSCMinted);

        if (maxDscToMint <= 0) {
            return;
        }
        Amount = bound(Amount, 1, uint256(maxDscToMint));
        vm.startPrank(Sender);
        Engine.mintDsc(Amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // Redeem Collateral Flowchart:-

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = Engine.getCollateralBalanceOfUser(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        Engine.redeemCollateral(address(collateral), amountCollateral);
    }

    // THIS BREAKS OUR INVARIANT SUITE!!!

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 NewPrice = int256(uint256(newPrice));
    //     EthUSDPriceFeed.updateAnswer(NewPrice);
    // }

    // Helper Function :- This will help to deposit only the valid collateral addresses instead of any random collateral address.

    function _getCollateralFromSeed(uint256 CollateralSeed) private view returns (ERC20Mock) {
        if (CollateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
