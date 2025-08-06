// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {DSCEngine, AggregatorV3Interface} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {console} from "forge-std/console.sol";

contract Handler is Test {
    // Deployed contracts to interact with
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    // Ghost Variables
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    // Keep track of calls and users
    uint256 public ghost_mintAndDepositCollateralCalls;
    address[] public usersWithCollateralDeposited;
    mapping(address => uint256) public userWethDeposited;
    mapping(address => uint256) public userWbtcDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    // Simplify the function signature and add error handling
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // This will definitely be called - let's see if we can get it to work
        console.log("HANDLER FUNCTION CALLED - depositCollateral");
        ghost_mintAndDepositCollateralCalls++;

        // Bound the amount to reasonable values
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        console.log("Selected collateral:", address(collateral));
        console.log("Amount:", amountCollateral);

        // Use a consistent user address
        address user = address(0x1); // Use a fixed address for simplicity

        // Mint tokens
        collateral.mint(user, amountCollateral);
        console.log("Minted tokens");

        // Start acting as the user
        vm.startPrank(user);

        // Approve the DSCEngine
        bool approveSuccess = collateral.approve(address(dscEngine), amountCollateral);
        console.log("Approve success:", approveSuccess);

        // Try to deposit - wrap in try/catch to see what's failing
        try dscEngine.depositCollateral(address(collateral), amountCollateral) {
            console.log("Deposit successful");

            // Track the deposit
            if (address(collateral) == address(weth)) {
                userWethDeposited[user] += amountCollateral;
            } else {
                userWbtcDeposited[user] += amountCollateral;
            }

            // Add user to list if not already there
            bool userExists = false;
            for (uint256 i = 0; i < usersWithCollateralDeposited.length; i++) {
                if (usersWithCollateralDeposited[i] == user) {
                    userExists = true;
                    break;
                }
            }
            if (!userExists) {
                usersWithCollateralDeposited.push(user);
            }
        } catch Error(string memory reason) {
            console.log("Deposit failed with reason:", reason);
        } catch {
            console.log("Deposit failed with unknown error");
        }

        vm.stopPrank();
    }

    // Add a simple function that should definitely work
    function doNothing() external pure {
        console.log("HANDLER: doNothing called");
        // This function does nothing but should be callable
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        console.log("HANDLER: redeemCollateral called");

        // Only proceed if we have users with collateral
        if (usersWithCollateralDeposited.length == 0) {
            console.log("No users with collateral deposited");
            return;
        }

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // Find a user who has this type of collateral
        address user = address(0);
        uint256 maxRedeemable = 0;

        for (uint256 i = 0; i < usersWithCollateralDeposited.length; i++) {
            address currentUser = usersWithCollateralDeposited[i];
            uint256 userBalance;

            if (address(collateral) == address(weth)) {
                userBalance = userWethDeposited[currentUser];
            } else {
                userBalance = userWbtcDeposited[currentUser];
            }

            if (userBalance > maxRedeemable) {
                maxRedeemable = userBalance;
                user = currentUser;
            }
        }

        // If no user has this collateral type, return
        if (user == address(0) || maxRedeemable == 0) {
            console.log("No user has this collateral type");
            return;
        }

        // Bound the amount to what the user actually has
        amountCollateral = bound(amountCollateral, 1, maxRedeemable);

        vm.prank(user);
        try dscEngine.redeemCollateral(address(collateral), amountCollateral) {
            console.log("Redeem successful");

            // Update our tracking
            if (address(collateral) == address(weth)) {
                userWethDeposited[user] -= amountCollateral;
            } else {
                userWbtcDeposited[user] -= amountCollateral;
            }
        } catch Error(string memory reason) {
            console.log("Redeem failed with reason:", reason);
        } catch {
            console.log("Redeem failed with unknown error");
        }
    }

    function mintDsc(uint256 amountDsc) public {
        console.log("HANDLER: mintDsc called");

        // Only proceed if we have users with collateral deposited
        if (usersWithCollateralDeposited.length == 0) {
            console.log("No users with collateral to mint DSC");
            return;
        }

        // Pick a random user who has collateral
        address user = usersWithCollateralDeposited[amountDsc % usersWithCollateralDeposited.length];

        // Get the user's account information
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);

        console.log("User:", user);
        console.log("Current DSC minted:", totalDscMinted);
        console.log("Collateral value in USD:", collateralValueInUsd);

        // Calculate max DSC this user can mint (assuming 200% overcollateralization)
        // DSC system typically requires 2x collateral, so max mintable = collateralValue / 2
        if (collateralValueInUsd == 0) {
            console.log("User has no collateral value");
            return;
        }

        uint256 maxMintable = (collateralValueInUsd / 2);

        if (totalDscMinted >= maxMintable) {
            console.log("User already at max DSC mint capacity");
            return;
        }

        uint256 availableToMint = maxMintable - totalDscMinted;

        // Bound the amount to what's actually available to mint
        amountDsc = bound(amountDsc, 1, availableToMint);

        console.log("Attempting to mint DSC:", amountDsc);
        console.log("Available to mint:", availableToMint);

        // Use the DSCEngine to mint DSC (not direct minting)
        vm.prank(user);
        try dscEngine.mintDsc(amountDsc) {
            console.log("DSC mint successful");
        } catch Error(string memory reason) {
            console.log("DSC mint failed with reason:", reason);
        } catch {
            console.log("DSC mint failed with unknown error");
        }
    }

    // Add another simple function with basic logic
    function simpleCall() external {
        console.log("HANDLER: simpleCall executed");
        // Just update a storage variable
        ghost_mintAndDepositCollateralCalls++;
    }

    /// Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
