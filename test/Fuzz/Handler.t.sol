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

contract Handler is Test {
    DSCEngine Engine;
    DecentralizedStableCoin DSC;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _Engine, DecentralizedStableCoin _DSC) {
        Engine = _Engine;
        DSC = _DSC;

        address[] memory CollateralToken = Engine.getCollateralTokens();
        weth = ERC20Mock(CollateralToken[0]);
        wbtc = ERC20Mock(CollateralToken[1]);
    }

    // Redeem Collateral flowchart -->

    function depositCollateral(uint256 CollateralSeed, uint256 amountCollateral) public {
        ERC20Mock Collateral = _getCollateralFromSeed(CollateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);

        Collateral.mint(msg.sender, amountCollateral);

        Collateral.approve(address(Engine), amountCollateral);

        Engine.depositCollateral(address(Collateral), amountCollateral);
        vm.stopPrank();
    }

    // Helper Function :- This will help to deposit only the valid collateral addresses instead of any random collateral address.

    function _getCollateralFromSeed(uint256 CollateralSeed) private view returns (ERC20Mock) {
        if (CollateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
