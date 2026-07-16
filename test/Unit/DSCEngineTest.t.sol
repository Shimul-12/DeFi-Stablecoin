//SPDX-Lincense-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../Mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed,, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, 100e18);
    }

    ///////////////////CONSTRUCTOR TESTS////////////////////

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed];

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////// PRICE TESTS //////////////////////
    function testgetUSDValue() public view {
        uint256 amount = 15e18;
        uint256 usdValue = engine.getUSDValue(weth, amount);
        assertEq(usdValue, amount * 2000);
    }

    function testGetTokenAmountFromUsd() public {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = engine.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    /////////////////// DEPOSIT COLLATERAL TESTS //////////////////////
    function testDepositCollateral() public {
        uint256 amount = 15e18;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amount);
        engine.depositCollateral(weth, amount);
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        uint256 amount = 0;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amount);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, amount);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RANDOM", "RAN", USER, 10 ether);

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), 10 ether);
        vm.stopPrank();
    }
}
