//SPDX-Lincense-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, , weth, , ) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, 100e18);
    }

    /////////////////// PRICE TESTS //////////////////////
    function testgetUSDValue() public view {
        uint256 amount = 15e18;
        uint256 usdValue = engine.getUSDValue(weth, amount);
        assertEq(usdValue, amount * 2000);
    }

    /////////////////// DEPOSIT COLLATERAL TESTS //////////////////////
    function testDepositCollateral() public {
        uint256 amount = 15e18;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amount);
        engine.depositCollateral(weth, amount);
        vm.stopPrank();
    }
}
