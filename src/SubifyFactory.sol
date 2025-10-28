// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionManager} from  "./SubscriptionManager.sol";
import {AccessPassNFT} from "./AccessPassNFT.sol";
import {CreatorRegistry} from "./CreatorRegistry.sol";

/**
 * @title SubifyFactory
 * @notice Factory contract for deploying the complete Subify ecosystem
 * @dev Deploys and wires together all system contracts
 */
contract SubifyFactory {
    
    // ============ Events ============
    
    event SubifyDeployed(
        address indexed subscriptionManager,
        address indexed accessPassNFT,
        address indexed creatorRegistry,
        address deployer
    );
    
    // ============ State Variables ============
    
    struct DeployedContracts {
        address subscriptionManager;
        address accessPassNFT;
        address creatorRegistry;
        uint256 deploymentTime;
    }
    
    DeployedContracts public deployment;
    
    // ============ Constructor ============
    
    constructor() {}
    
    // ============ Deployment Function ============
    
    /**
     * @notice Deploy the complete Subify ecosystem
     * @param paymentToken Address of the ERC20 token for payments (USDC, DAI, etc.)
     * @return subscriptionManager Address of SubscriptionManager
     * @return accessPassNFT Address of AccessPassNFT
     * @return creatorRegistry Address of CreatorRegistry
     */
    function deploySubify(address paymentToken) 
        external 
        returns (
            address subscriptionManager,
            address accessPassNFT,
            address creatorRegistry
        ) 
    {
        // Deploy CreatorRegistry
        CreatorRegistry registry = new CreatorRegistry();
        creatorRegistry = address(registry);
        
        // Deploy AccessPassNFT
        AccessPassNFT nft = new AccessPassNFT();
        accessPassNFT = address(nft);
        
        // Deploy SubscriptionManager
        SubscriptionManager manager = new SubscriptionManager(paymentToken);
        subscriptionManager = address(manager);
        
        // Wire contracts together
        manager.setAccessPassNFT(accessPassNFT);
        nft.grantRole(nft.MINTER_ROLE(), subscriptionManager);
        
        // Transfer ownership to deployer
        manager.transferOwnership(msg.sender);
        registry.transferOwnership(msg.sender);
        nft.grantRole(nft.DEFAULT_ADMIN_ROLE(), msg.sender);
        nft.revokeRole(nft.DEFAULT_ADMIN_ROLE(), address(this));
        
        // Store deployment info
        deployment = DeployedContracts({
            subscriptionManager: subscriptionManager,
            accessPassNFT: accessPassNFT,
            creatorRegistry: creatorRegistry,
            deploymentTime: block.timestamp
        });
        
        emit SubifyDeployed(
            subscriptionManager,
            accessPassNFT,
            creatorRegistry,
            msg.sender
        );
        
        return (subscriptionManager, accessPassNFT, creatorRegistry);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get deployed contract addresses
     */
    function getDeployment() external view returns (DeployedContracts memory) {
        return deployment;
    }
}