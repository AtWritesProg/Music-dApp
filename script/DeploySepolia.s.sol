// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";
import {AccessPassNFT} from "../src/AccessPassNFT.sol";
import {CreatorRegistry} from "../src/CreatorRegistry.sol";

/**
 * @title DeploySepolia
 * @notice Deployment script for Subify contracts on Sepolia testnet
 * @dev Run with: forge script script/DeploySepolia.s.sol:DeploySepolia --rpc-url sepolia --broadcast --verify -vvvv
 */
contract DeploySepolia is Script {
    // Sepolia USDC address (Circle's USDC on Sepolia)
    // If this doesn't exist, we'll need to deploy a mock
    address constant SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    // Deployment addresses (will be filled after deployment)
    SubscriptionManager public subscriptionManager;
    AccessPassNFT public accessPassNFT;
    CreatorRegistry public creatorRegistry;

    function run() external {
        // Load deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("========================================");
        console2.log("Deploying Subify to Sepolia Testnet");
        console2.log("========================================");
        console2.log("Deployer address:", deployer);
        console2.log("Deployer balance:", deployer.balance);
        console2.log("Payment Token (USDC):", SEPOLIA_USDC);
        console2.log("========================================");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy CreatorRegistry
        console2.log("\n1. Deploying CreatorRegistry...");
        creatorRegistry = new CreatorRegistry();
        console2.log("CreatorRegistry deployed at:", address(creatorRegistry));

        // 2. Deploy AccessPassNFT
        console2.log("\n2. Deploying AccessPassNFT...");
        accessPassNFT = new AccessPassNFT();
        console2.log("AccessPassNFT deployed at:", address(accessPassNFT));

        // 3. Deploy SubscriptionManager
        console2.log("\n3. Deploying SubscriptionManager...");
        subscriptionManager = new SubscriptionManager(SEPOLIA_USDC);
        console2.log("SubscriptionManager deployed at:", address(subscriptionManager));

        // 4. Wire contracts together
        console2.log("\n4. Wiring contracts together...");

        // Set AccessPassNFT in SubscriptionManager
        subscriptionManager.setAccessPassNFT(address(accessPassNFT));
        console2.log("Set AccessPassNFT in SubscriptionManager");

        // Grant MINTER_ROLE to SubscriptionManager
        bytes32 minterRole = accessPassNFT.MINTER_ROLE();
        accessPassNFT.grantRole(minterRole, address(subscriptionManager));
        console2.log("Granted MINTER_ROLE to SubscriptionManager");

        vm.stopBroadcast();

        // 5. Log deployment summary
        console2.log("\n========================================");
        console2.log("Deployment Summary");
        console2.log("========================================");
        console2.log("Network: Sepolia Testnet");
        console2.log("Deployer:", deployer);
        console2.log("Payment Token:", SEPOLIA_USDC);
        console2.log("");
        console2.log("Deployed Contracts:");
        console2.log("- SubscriptionManager:", address(subscriptionManager));
        console2.log("- AccessPassNFT:", address(accessPassNFT));
        console2.log("- CreatorRegistry:", address(creatorRegistry));
        console2.log("");
        console2.log("Contract Owners:");
        console2.log("- SubscriptionManager owner:", subscriptionManager.owner());
        console2.log("- CreatorRegistry owner:", creatorRegistry.owner());
        console2.log("- AccessPassNFT admin:", deployer);
        console2.log("");
        console2.log("Configuration:");
        console2.log("- Platform Fee:", subscriptionManager.s_platformFeePercent(), "bps (basis points)");
        console2.log("- Registration Fee:", creatorRegistry.s_registrationFee(), "wei");
        console2.log("========================================");
        console2.log("\nVerification commands:");
        console2.log("forge verify-contract", address(subscriptionManager), "src/SubscriptionManager.sol:SubscriptionManager --chain sepolia --watch");
        console2.log("forge verify-contract", address(accessPassNFT), "src/AccessPassNFT.sol:AccessPassNFT --chain sepolia --watch");
        console2.log("forge verify-contract", address(creatorRegistry), "src/CreatorRegistry.sol:CreatorRegistry --chain sepolia --watch");
        console2.log("========================================");

        // Save deployment addresses to file
        _saveDeployment(deployer);
    }

    function _saveDeployment(address deployer) internal {
        string memory json = string(abi.encodePacked(
            '{\n',
            '  "network": "sepolia",\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "timestamp": ', vm.toString(block.timestamp), ',\n',
            '  "contracts": {\n',
            '    "SubscriptionManager": "', vm.toString(address(subscriptionManager)), '",\n',
            '    "AccessPassNFT": "', vm.toString(address(accessPassNFT)), '",\n',
            '    "CreatorRegistry": "', vm.toString(address(creatorRegistry)), '",\n',
            '    "PaymentToken": "', vm.toString(SEPOLIA_USDC), '"\n',
            '  }\n',
            '}'
        ));
        vm.writeFile("./deployments/sepolia-latest.json", json);
        console2.log("\nDeployment info saved to: ./deployments/sepolia-latest.json");
    }
}
