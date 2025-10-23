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

    IERC20 public s_paymentToken; // USDC, DAI, etc
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

    event SubscriptionCancelled(uint256 indexed subscriptionId, address indexed subscriber, address indexed creator);

    event TierCreated(address indexed creator, uint256 tierId, uint256 price, uint256 duration, string name);

    event FundsWithdrawn(address indexed creator, uint256 amount);

    event SubscriptionRenewed(uint256 indexed subscriptionId, uint256 newEndTime);
    event PlatformFeeUpdated(uint256 newFee);

    //============Errors=================
    error InvalidPrice();
    error InvalidDuration();
    error InvalidTier();
    error InsufficientBalance();
    error SubscriptionExists();
    error NoActiveSubscription();
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
    function createTier(uint256 _price, uint256 _duration, string calldata _name) external whenNotPaused {
        if (_price == 0) revert InvalidPrice();
        if (_duration == 0) revert InvalidDuration();

        uint256 tierId = creatorTierCount[msg.sender]++;

        creatorTier[msg.sender][tierId] = CreatorTier({price: _price, duration: _duration, name: _name, isActive: true});

        emit TierCreated(msg.sender, tierId, _price, _duration, _name);
    }

    /**
     * @notice Update an existing Tier
     */
    function updateTier(uint256 tierId, uint256 newPrice, uint256 newDuration, bool active) external {
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

        emit FundsWithdrawn(msg.sender, balance);
    }

    // =============== Subscriber Functions ===============

    /**
     * @notice Subscribe to a creator's tier
     * @param creator Address of the creator
     * @param tierId Tier ID to subscribe to
     * @param autoRenew Enables automatic Renewal
     */
    function subscribe(address creator, uint256 tierId, bool autoRenew)
        external
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        if (tierId >= creatorTierCount[creator]) revert InvalidTier();
        if (activeSubscription[msg.sender][creator] != 0) revert SubscriptionExists();

        CreatorTier memory tier = creatorTier[creator][tierId];
        if (!tier.isActive) revert InvalidTier();

        //Calculate fees
        uint256 platformFee = (tier.price * s_platformFeePercent) / FEE_DENOMINATOR;
        uint256 creatorAmount = tier.price - platformFee;

        // Transfer payment
        bool success = s_paymentToken.transferFrom(msg.sender, address(this), tier.price);
        require(success, "Payment transfer failed");

        // Update creator balance
        creatorBalances[creator] += creatorAmount;
        creatorBalances[owner()] += platformFee;

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

        emit SubscriptionCreated(subscriptionId, msg.sender, creator, tierId, tier.price, endTime);

        return subscriptionId;
    }

    /**
     * @notice Cancel an active subscription
     * @param creator Address of the creator
     */
    function cancelSubscription(address creator) external {
        uint256 subscriptionId = activeSubscription[msg.sender][creator];
        if (subscriptionId == 0) revert NoActiveSubscription();

        Subscription storage sub = subscriptions[subscriptionId];
        if (!sub.isActive) revert NoActiveSubscription();

        sub.isActive = false;
        sub.autoRenew = false;
        delete activeSubscription[msg.sender][creator];
        subscriberCount[creator]--;

        emit SubscriptionCancelled(subscriptionId, msg.sender, creator);
    }

    /**
     * @notice Manually renew a subscription
     * @param creator Address of creator
     */
    function renewSubscription(address creator) external nonReentrant whenNotPaused {
        uint256 subscriptionId = activeSubscription[msg.sender][creator];
        if (subscriptionId == 0) revert NoActiveSubscription();

        Subscription storage sub = subscriptions[subscriptionId];
        if (!sub.isActive) revert NoActiveSubscription();

        CreatorTier memory tier = creatorTier[creator][sub.tier];
        if (!tier.isActive) revert InvalidTier();

        // Calculate fees
        uint256 platformFee = (tier.price * s_platformFeePercent) / FEE_DENOMINATOR;
        uint256 creatorAmount = tier.price - platformFee;

        // Transfer payment
        bool success = s_paymentToken.transferFrom(msg.sender, address(this), tier.price);
        require(success, "Payment transfer failed");

        // Update balances
        creatorBalances[creator] += creatorAmount;
        creatorBalances[owner()] += platformFee;

        // Extend subscription
        uint256 newEndTime =
            block.timestamp > sub.endTime ? block.timestamp + tier.duration : sub.endTime + tier.duration;

        sub.endTime = newEndTime;

        emit SubscriptionRenewed(subscriptionId, newEndTime);
    }

    // ============ View Functions ============

    /**
     * @notice Check if a subscription is currently active
     */
    function isSubscriptionActive(address subscriber, address creator) external view returns (bool) {
        uint256 subscriptionId = activeSubscription[subscriber][creator];
        if (subscriptionId == 0) return false;

        Subscription memory sub = subscriptions[subscriptionId];
        return sub.isActive && block.timestamp <= sub.endTime;
    }

    /**
     * @notice Get subscription details
     */
    function getSubscription(uint256 subscriptionId) external view returns (Subscription memory) {
        return subscriptions[subscriptionId];
    }

    /**
     * @notice Get tier details
     */
    function getTier(address creator, uint256 tierId) external view returns (CreatorTier memory) {
        return creatorTier[creator][tierId];
    }

    /**
     * @notice Get all tiers for a creator
     */
    function getCreatorTiers(address creator) external view returns (CreatorTier[] memory) {
        uint256 count = creatorTierCount[creator];
        CreatorTier[] memory tiers = new CreatorTier[](count);

        for (uint256 i = 0; i < count; i++) {
            tiers[i] = creatorTier[creator][i];
        }

        return tiers;
    }

    // ============ Admin Functions ============

    /**
     * @notice Update platform fee percentage
     */
    function updatePlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        s_platformFeePercent = newFee;
        emit PlatformFeeUpdated(newFee);
    }

    /**
     * @notice Set AccessPass NFT contract address
     */
    function setAccessPassNFT(address _accessPassNFT) external onlyOwner {
        s_accessPassNFT = _accessPassNFT;
    }

    /**
     * @notice Pause contract in emergency
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
