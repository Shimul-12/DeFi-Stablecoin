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

contract InvariantsTest is StdInvariant, Test {
    DeployDSC Deployer;
    DSCEngine Engine;
    DecentralizedStableCoin DSC;
    HelperConfig Config;

    function setUp() external {
        // Deploy the contracts first.
        Deployer = new DeployDSC();
        (DSC, Engine, Config) = Deployer.run();
        targetContract(address(Engine));
    }

    function invariant_protocolMustHaveMoreCollateralThanTotalSupply() public view {
        // Get the value of all the collateral in the protocol.
        // Compare it to all the debt (DSC).
    }
}
