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

    /**
     * @notice Deactivate creator profile 
     */
    function deactivateProfile() external {
        if (!isRegistered[msg.sender]) revert NotRegistered();
        
        creators[msg.sender].isActive = false;
        
        emit CreatorDeactivated(msg.sender);
    }

    /**
     * @notice Reactivate creator profile
     */
    function reactivateProfile() external {
        if (!isRegistered[msg.sender]) revert NotRegistered();
        
        creators[msg.sender].isActive = true;
        
        emit CreatorReactivated(msg.sender);
    }

    /**
     * @notice Update creator statistics
     * @dev Should be called by SubscriptionManager contract
     */
    function updateCreatorStats(
        address creator,
        uint256 subscriberDelta,
        uint256 revenueDelta,
        bool isIncrement
    ) external {
        if (!isRegistered[creator]) revert NotRegistered();

        CreatorProfile storage profile = creators[creator];

        if (isIncrement) {
            profile.totalSubscribers += subscriberDelta;
            profile.totalRevenue += revenueDelta;
        } else {
            profile.totalSubscribers -= subscriberDelta;
        }

        emit StatsUpdated(creator, profile.totalSubscribers, profile.totalRevenue);
    }

    //==================View Functions ===================

    /**
     * @notice Get creator profile
     */
    function getCreatorProfile(address creator) external view returns (CreatorProfile memory) {
        return creators[creator];
    }

    /**
     * @notice Get all registered creators
     */
    function getAllCreators() external view returns (address[] memory) {
        return creatorList;
    }
    
    /**
     * @notice Get active creators only
     */
    function getActiveCreators() external view returns (address[] memory) {
        uint256 activeCount = 0;
        
        // Count active creators
        for (uint256 i = 0; i < creatorList.length; i++) {
            if (creators[creatorList[i]].isActive) {
                activeCount++;
            }
        }
        
        // Create array of active creators
        address[] memory activeCreators = new address[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < creatorList.length; i++) {
            if (creators[creatorList[i]].isActive) {
                activeCreators[index] = creatorList[i];
                index++;
            }
        }
        
        return activeCreators;
    }
    
    /**
     * @notice Get verified creators only
     */
    function getVerifiedCreators() external view returns (address[] memory) {
        uint256 verifiedCount = 0;
        
        // Count verified creators
        for (uint256 i = 0; i < creatorList.length; i++) {
            if (creators[creatorList[i]].isVerified && creators[creatorList[i]].isActive) {
                verifiedCount++;
            }
        }
        
        // Create array of verified creators
        address[] memory verifiedCreators = new address[](verifiedCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < creatorList.length; i++) {
            if (creators[creatorList[i]].isVerified && creators[creatorList[i]].isActive) {
                verifiedCreators[index] = creatorList[i];
                index++;
            }
        }
        
        return verifiedCreators;
    }
    
    /**
     * @notice Search creators by name (off-chain indexing recommended)
     */
    function getCreatorByAddress(address creator) 
        external 
        view 
        returns (
            string memory name,
            string memory metadataURI,
            bool verified,
            bool active,
            uint256 totalSubscribers
        ) 
    {
        CreatorProfile memory profile = creators[creator];
        return (
            profile.name,
            profile.metadataURI,
            profile.isVerified,
            profile.isActive,
            profile.totalSubscribers
        );
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Verify a creator (blue checkmark)
     */
    function verifyCreator(address creator) external onlyOwner {
        if (!isRegistered[creator]) revert NotRegistered();
        
        creators[creator].isVerified = true;
        isVerified[creator] = true;
        
        emit CreatorVerified(creator);
    }
    
    /**
     * @notice Remove verification from a creator
     */
    function unverifyCreator(address creator) external onlyOwner {
        if (!isRegistered[creator]) revert NotRegistered();
        
        creators[creator].isVerified = false;
        isVerified[creator] = false;
        
        emit CreatorUnverified(creator);
    }
    
    /**
     * @notice Update registration fee
     */
    function updateRegistrationFee(uint256 newFee) external onlyOwner {
        s_registrationFee = newFee;
    }
    
    /**
     * @notice Withdraw accumulated registration fees
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}