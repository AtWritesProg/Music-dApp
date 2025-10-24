// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title CreatorRegistry
 * @notice Registry for verified music creator and their profile
 * @dev Handles creator verification, profiles, and reputation
 */

abstract contract CreatorRegistry is Ownable, Pausable {
    //========= State Variables ===========
    uint256 public s_registrationFee = 0.01 ether;  //Anti-spam measure
    uint256 public s_creatorCount;

    //========= Structs ==========
    struct CreatorProfile {
        string name;
        string metadataURI;
        address wallet;
        uint256 registrationTime;
        bool isVerified;
        bool isActive;
        uint256 totalSubscribers;
        uint256 totalRevenue;
        string[] socialLinks;
    }

    struct CreatorStats {
        uint256 monthlySubscribers;
        uint256 monthlyRevenue;
        uint256 lifetimeSubscribers;
        uint256 averageSubscriptionDuration;
        uint256 retentionRate; // Basis points (e.g., 7500 = 75%)
    }

    //=========Mappings=========

    // creator address => CreatorProfile
    mapping(address => CreatorProfile) public creators;

    // creator address => CreatorStats
    mapping(address => CreatorProfile) public creatorStats;

    // creator address => isRegistered
    mapping(address => bool) public isRegistered;

    // creator address => isVerified
    mapping(address => bool) public isVerified;
    
    // Array of all creator addresses
    address[] public creatorList;

    //============Events=============
    event CreatorRegistered(
        address indexed creator,
        string name,
        string metadataURI
    );
    
    event CreatorVerified(address indexed creator);
    
    event CreatorUnverified(address indexed creator);
    
    event ProfileUpdated(
        address indexed creator,
        string metadataURI
    );
    
    event CreatorDeactivated(address indexed creator);
    
    event CreatorReactivated(address indexed creator);
    
    event StatsUpdated(
        address indexed creator,
        uint256 totalSubscribers,
        uint256 totalRevenue
    );

    //=========Errors==========
    error AlreadyRegistered();
    error InsufficientFee();
    error NotRegistered();

    //=========Constructor=============
    constructor() {}

    // =============Creator Functions==============

    /**
     * @notice Register as a new creator
     * @param name Creator's display name
     * @param metadataURI IPFS URI containing profile data
     * @param socialLinks Array of social media links
     */
    function registerCreator(
        string calldata name,
        string calldata metadataURI,
        string[] calldata socialLinks
    ) external payable whenNotPaused {
        if (isRegistered[msg.sender]) revert AlreadyRegistered();
        if (msg.value < s_registrationFee) revert InsufficientFee();

        creators[msg.sender] = CreatorProfile({
            name: name,
            metadataURI: metadataURI,
            wallet: msg.sender,
            registrationTime: block.timestamp,
            isVerified: false,
            isActive: true,
            totalSubscribers: 0,
            totalRevenue: 0,
            socialLinks: socialLinks
        });

        isRegistered[msg.sender] = true;
        creatorList.push(msg.sender);
        s_creatorCount++;

        emit CreatorRegistered(msg.sender, name, metadataURI);
    }

    /**
     * @notice Update creator profile
     * @param metadataURI New IPFS URI
     * @param socialLinks Updated social Links
     */
    function updateProfile(
        string calldata metadataURI,
        string[] calldata socialLinks
    ) external {
        if(!isRegistered[msg.sender]) revert NotRegistered();

        CreatorProfile storage profile = creators[msg.sender];
        profile.metadataURI = metadataURI;
        profile.socialLinks = socialLinks;

        emit ProfileUpdated(msg.sender, metadataURI);
    }
}