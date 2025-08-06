// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    Handler handler;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dsce, dsc);

        // Target the handler contract
        targetContract(address(handler));

        // Let's also try targeting specific selectors
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = Handler.depositCollateral.selector;
        selectors[1] = Handler.redeemCollateral.selector;
        selectors[2] = Handler.mintDsc.selector;
        selectors[3] = Handler.doNothing.selector;
        selectors[4] = Handler.simpleCall.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        console.log("=== Setup Complete ===");
        console.log("Handler address:", address(handler));
        console.log("DSCEngine address:", address(dsce));
        console.log("depositCollateral selector:", uint32(Handler.depositCollateral.selector));
        console.log("redeemCollateral selector:", uint32(Handler.redeemCollateral.selector));
        console.log("doNothing selector:", uint32(Handler.doNothing.selector));
        console.log("simpleCall selector:", uint32(Handler.simpleCall.selector));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupplyDollars() public view {
        console.log("=== INVARIANT CHECK START ===");

        // Check if any handler functions were called
        uint256 handlerCalls = handler.ghost_mintAndDepositCollateralCalls();
        console.log("Handler function calls:", handlerCalls);

        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposited = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, wethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, wbtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
    }

    // Add a simple test to verify the handler is working
    function test_handlerWorks() public {
        console.log("Testing handler directly...");
        handler.simpleCall();
        handler.doNothing();

        uint256 calls = handler.ghost_mintAndDepositCollateralCalls();
        console.log("Direct handler calls:", calls);
        assertGt(calls, 0);
    }
}
