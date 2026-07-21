// SPDX-License-Identifier: MIT

// Have our invariants here aka properties hold true for all the time.

// What are our invariants (properties)?

// 1. The total supply of DSC is always less than the total collateral value.
// 2. Getter view function should always revert for an address that doesn't have any collateral or DSC. <-- Evergreen invariant.

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC Deployer;
    DSCEngine Engine;
    DecentralizedStableCoin DSC;
    HelperConfig Config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        // Deploy the contracts first.
        Deployer = new DeployDSC();
        (DSC, Engine, Config) = Deployer.run();
        (, , weth, wbtc, ) = Config.activeNetworkConfig();
        // targetContract(address(Engine));
        handler = new Handler(Engine, DSC);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreCollateralThanTotalSupply()
        public
        view
    {
        // 1. Get the Total DSC supply.
        // 2. Get the total WETH in the protocol. (In USD)
        // 3. Get the total WBTC in the protocol. (In USD)
        // 4. Compare it to all the debt (DSC).

        uint256 totalSupply = DSC.totalSupply();

        uint256 WethDeposited = IERC20(weth).balanceOf(address(Engine));
        uint256 WbtcDeposited = IERC20(wbtc).balanceOf(address(Engine));

        uint256 WethValue = Engine.getUSDValue(weth, WethDeposited);
        uint256 WbtcValue = Engine.getUSDValue(wbtc, WbtcDeposited);

        console.log("Weth Value :", WethValue);
        console.log("Wbtc Value :", WbtcValue);
        console.log("Total Supply :", totalSupply);
        console.log("Times Mint Is Called :", handler.timesMintIsCalled());

        assert(WethValue + WbtcValue >= totalSupply);
    }
}
