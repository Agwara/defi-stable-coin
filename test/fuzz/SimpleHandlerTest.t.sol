// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract SimpleHandlerTest is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
    }

    function test_handlerCanDeposit() public {
        console.log("Testing direct handler deposit...");

        // Call the handler function directly
        handler.depositCollateral(0, 1 ether); // 0 for WETH, 1 ether amount

        // Check if deposit worked
        uint256 wethBalance = ERC20Mock(weth).balanceOf(address(dsce));
        console.log("WETH deposited:", wethBalance);

        uint256 calls = handler.ghost_mintAndDepositCollateralCalls();
        console.log("Handler calls made:", calls);

        assertGt(calls, 0, "Handler should have been called");
    }
}
