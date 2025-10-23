//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SubscriptionManager
 * @notice Manages recurring subscriptions for music creators.
 * @dev Handles subscription payments, renewals, and cancellations.
 */

abstract contract SubscriptionManager is Ownable, ReentrancyGuard, Pausable {
    
    // ================ State Variables ====================

    IERC20 public s_paymentToken;   // USDC, DAI, etc
    address public s_accessPassNFT; // NFT Contract address

    uint256 public s_platformFeePercent = 300; // 3% (basis points)
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public s_subscriptionCounter;

    //==================Structs====================

    struct Subscription {
        uint256 id;
        address subscriber;
        address creator;
        uint256 tier;
        uint256 startTime;
        uint256 endTime;
        uint256 amount;
        bool isActive;
        bool autoRenew;
    }

    struct CreatorTier {
        uint256 price;
        uint256 duration;
        string name;
        bool isActive;
    }

    //===============Mappings==================
    
    // SubID => Subscription
    mapping(uint256 => Subscription) public subscriptions;

    // subscriber => creator => SubId
    mapping(address => mapping(address => uint256)) public activeSubscription;

    // creator => tier => CreatorTier
    mapping(address => mapping(uint256 => CreatorTier)) public creatorTier;

    // creator => number of tiers
    mapping(address => uint256) public creatorTierCount;
    
    // creator => withdrawable balance
    mapping(address => uint256) public creatorBalances;

    // creator => total subscribers
    mapping(address => uint256) public subscriberCount;

    //=============Events================

    event SubscriptionCreated(
        uint256 indexed subscriptionId,
        address indexed subscriber,
        address indexed creator,
        uint256 tier,
        uint256 amount,
        uint256 endTime
    );

    event SubscriptionCancelled(
        uint256 indexed subscriptionId,
        address indexed subscriber,
        address indexed creator
    );

    event TierCreated(
        address indexed creator,
        uint256 tierId,
        uint256 price,
        uint256 duration,
        string name
    );
    
    event FundsWithdrawn(
        address indexed creator,
        uint256 amount
    );
    
    event PlatformFeeUpdated(uint256 newFee);

    //============Errors=================
    error InvalidPrice();
    error InvalidDuration();
    error InvalidTier();
    error InsufficientBalance();
    error SubscriptionExists();
    //============Constructor==============

    constructor(address _paymentToken) {
        s_paymentToken = IERC20(_paymentToken);
    }

    // ============ Creator Functions =============

    /**
     * @notice Creates a new subscription tier.
     * @param _price Price of the tier in payment token.
     * @param _duration Duration of the tier in seconds.
     * @param _name Name of the tier.
     */
    function createTier(
        uint256 _price,
        uint256 _duration,
        string calldata _name
    ) external whenNotPaused {
        if (_price == 0) revert InvalidPrice();
        if (_duration == 0) revert InvalidDuration();

        uint256 tierId = creatorTierCount[msg.sender]++;

        creatorTier[msg.sender][tierId] = CreatorTier({
            price: _price,
            duration: _duration,
            name: _name,
            isActive: true
        });

        emit TierCreated(msg.sender, tierId, _price, _duration, _name);
    }

    /**
     * @notice Update an existing Tier
     */
    function updateTier(
        uint256 tierId,
        uint256 newPrice,
        uint256 newDuration,
        bool active
    ) external {
        if (tierId >= creatorTierCount[msg.sender]) revert InvalidTier();
        if (newPrice == 0) revert InvalidPrice();
        if (newDuration == 0) revert InvalidDuration();

        CreatorTier storage tier = creatorTier[msg.sender][tierId];
        tier.price = newPrice;
        tier.duration = newDuration;
        tier.isActive = active;
    }

    /**
     * @notice Withdraw acccumlated subscription funds
     */
    function withdrawFunds() external nonReentrant {
        uint256 balance = creatorBalances[msg.sender];
        if (balance == 0) revert InsufficientBalance(); 

        creatorBalances[msg.sender] = 0;

        bool success = s_paymentToken.transfer(msg.sender, balance);
        require(success, "Transfer failed");

        emit FundsWithdrawn(msg.sender,balance);
    }

    // =============== Subscriber Functions ===============

    /**
     * @notice Subscribe to a creator's tier
     * @param creator Address of the creator
     * @param tierId Tier ID to subscribe to
     * @param autoRenew Enables automatic Renewal
     */

    function subscribe(
        address creator,
        uint256 tierId,
        bool autoRenew
    ) external nonReentrant whenNotPaused returns (uint256) {
        if (tierId >= creatorTierCount[creator]) revert InvalidTier();
        if (activeSubscription[msg.sender][creator] != 0) revert SubscriptionExists();

        CreatorTier memory tier = creatorTier[creator][tierId];
        if (!tier.isActive) revert InvalidTier();

        //Calculate fees
        uint256 platformFee = (tier.price * s_platformFeePercent) / FEE_DENOMINATOR;
        uint256 creatorAmount = tier.price - platformFee;

        // Create subscription
        uint256 subscriptionId = ++s_subscriptionCounter;
        uint256 endTime = block.timestamp + tier.duration;

        subscriptions[subscriptionId] = Subscription({
            id: subscriptionId,
            subscriber: msg.sender,
            creator: creator,
            tier: tierId,
            startTime: block.timestamp,
            endTime: endTime,
            amount: tier.price,
            isActive: true,
            autoRenew: autoRenew
        });

        activeSubscription[msg.sender][creator] = subscriptionId;
        subscriberCount[creator]++;
        
        emit SubscriptionCreated(
            subscriptionId,
            msg.sender,
            creator,
            tierId,
            tier.price,
            endTime
        );
        
        return subscriptionId;
    }
}
