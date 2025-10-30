// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SubscriptionManager.sol";
import "../src/AccessPassNFT.sol";
import "../src/CreatorRegistry.sol";

contract MockERC20 is Test {
    string public name = "Mock USDC";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract SubscriptionManagerTest is Test {
    SubscriptionManager public manager;
    AccessPassNFT public nft;
    CreatorRegistry public registry;
    MockERC20 public usdc;
    
    address public owner;
    address public creator;
    address public subscriber;
    address public subscriber2;
    
    uint256 constant TIER_PRICE = 10 * 10**6; // $10 USDC
    uint256 constant TIER_DURATION = 30 days;
    
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

    event SubscriptionRenewed(
        uint256 indexed subscriptionId,
        uint256 newEndTime
    );

    function setUp() public {
        owner = address(this);
        creator = makeAddr("creator");
        subscriber = makeAddr("subscriber");
        subscriber2 = makeAddr("subscriber2");
        
        // Deploy contracts
        usdc = new MockERC20();
        manager = new SubscriptionManager(address(usdc));
        nft = new AccessPassNFT();
        registry = new CreatorRegistry();
        
        // Setup NFT minter role
        nft.grantRole(nft.MINTER_ROLE(), address(manager));
        manager.setAccessPassNFT(address(nft));
        
        // Mint USDC to subscribers
        usdc.mint(subscriber, 1000 * 10**6); // 1000 USDC
        usdc.mint(subscriber2, 1000 * 10**6);
        
        // Creator creates a tier
        vm.prank(creator);
        manager.createTier(TIER_PRICE, TIER_DURATION, "Basic");
    }
    
    // function testCreateTier() public {
    //     vm.prank(creator);
    //     manager.createTier(20 * 10**6, 60 days, "Premium");
        
    //     (uint256 price, uint256 duration, string memory name, bool active) = 
    //         manager.creatorTiers(creator, 1);
        
    //     assertEq(price, 20 * 10**6);
    //     assertEq(duration, 60 days);
    //     assertEq(name, "Premium");
    //     assertTrue(active);
    // }
    
    function testCannotCreateTierWithZeroPrice() public {
        vm.prank(creator);
        vm.expectRevert(SubscriptionManager.InvalidPrice.selector);
        manager.createTier(0, 30 days, "Free");
    }
    
    function testCannotCreateTierWithZeroDuration() public {
        vm.prank(creator);
        vm.expectRevert(SubscriptionManager.InvalidDuration.selector);
        manager.createTier(10 * 10**6, 0, "Invalid");
    }
    
    function testSubscribe() public {
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        
        vm.expectEmit(true, true, true, false);
        emit SubscriptionCreated(1, subscriber, creator, 0, TIER_PRICE, 0);
        
        uint256 subId = manager.subscribe(creator, 0, true);
        vm.stopPrank();
        
        assertEq(subId, 1);
        assertTrue(manager.isSubscriptionActive(subscriber, creator));
        
        // Check subscription details
        (
            uint256 id,
            address sub,
            address cre,
            uint256 tier,
            ,
            uint256 endTime,
            uint256 amount,
            bool active,
            bool autoRenew
        ) = manager.subscriptions(subId);
        
        assertEq(id, 1);
        assertEq(sub, subscriber);
        assertEq(cre, creator);
        assertEq(tier, 0);
        assertEq(amount, TIER_PRICE);
        assertTrue(active);
        assertTrue(autoRenew);
        assertEq(endTime, block.timestamp + TIER_DURATION);
    }
    
    function testCannotSubscribeTwice() public {
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE * 2);
        manager.subscribe(creator, 0, false);
        
        vm.expectRevert(SubscriptionManager.SubscriptionExists.selector);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();
    }
    
    function testCannotSubscribeToInvalidTier() public {
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        
        vm.expectRevert(SubscriptionManager.InvalidTier.selector);
        manager.subscribe(creator, 99, false);
        vm.stopPrank();
    }
    
    function testCancelSubscription() public {
        // Subscribe first
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        
        // Cancel
        vm.expectEmit(true, true, true, false);
        emit SubscriptionCancelled(1, subscriber, creator);
        
        manager.cancelSubscription(creator);
        vm.stopPrank();
        
        assertFalse(manager.isSubscriptionActive(subscriber, creator));
        
        // Check subscription is marked inactive
        (,,,,,, , bool active,) = manager.subscriptions(1);
        assertFalse(active);
    }
    
    function testCannotCancelNonexistentSubscription() public {
        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.NoActiveSubscription.selector);
        manager.cancelSubscription(creator);
    }
    
    function testRenewSubscription() public {
        // Subscribe first
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE * 2);
        manager.subscribe(creator, 0, false);
        
        uint256 firstEndTime = block.timestamp + TIER_DURATION;
        
        // Fast forward 15 days
        vm.warp(block.timestamp + 15 days);
        
        // Renew
        manager.renewSubscription(creator);
        vm.stopPrank();
        
        (,,,,,uint256 endTime,,,) = manager.subscriptions(1);
        assertEq(endTime, firstEndTime + TIER_DURATION);
    }
    
    function testRenewAfterExpiry() public {
        // Subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE * 2);
        manager.subscribe(creator, 0, false);
        
        // Fast forward past expiry
        vm.warp(block.timestamp + TIER_DURATION + 1 days);
        
        // Renew should extend from current time
        manager.renewSubscription(creator);
        vm.stopPrank();
        
        (,,,,,uint256 endTime,,,) = manager.subscriptions(1);
        assertEq(endTime, block.timestamp + TIER_DURATION);
    }
    
    function testCreatorWithdrawFunds() public {
        // Two subscribers
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();
        
        vm.startPrank(subscriber2);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();
        
        // Calculate expected amount (minus 3% platform fee)
        uint256 platformFee = (TIER_PRICE * 300) / 10000;
        uint256 creatorAmount = TIER_PRICE - platformFee;
        uint256 expectedBalance = creatorAmount * 2;
        
        uint256 balanceBefore = usdc.balanceOf(creator);
        
        // Withdraw
        vm.prank(creator);
        manager.withdrawFunds();
        
        uint256 balanceAfter = usdc.balanceOf(creator);
        assertEq(balanceAfter - balanceBefore, expectedBalance);
        
        // Balance should be zero after withdrawal
        assertEq(manager.creatorBalances(creator), 0);
    }
    
    function testCannotWithdrawZeroBalance() public {
        vm.prank(creator);
        vm.expectRevert(SubscriptionManager.InsufficientBalance.selector);
        manager.withdrawFunds();
    }
    
    function testPlatformFeeCollection() public {
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();
        
        uint256 platformFee = (TIER_PRICE * 300) / 10000; // 3%
        assertEq(manager.creatorBalances(owner), platformFee);
    }
    
    function testUpdatePlatformFee() public {
        manager.updatePlatformFee(500); // 5%
        assertEq(manager.s_platformFeePercent(), 500);
    }
    
    function testCannotSetPlatformFeeTooHigh() public {
        vm.expectRevert("Fee too high");
        manager.updatePlatformFee(1001); // >10%
    }
    
    function testGetCreatorTiers() public {
        vm.startPrank(creator);
        manager.createTier(20 * 10**6, 60 days, "Premium");
        manager.createTier(50 * 10**6, 365 days, "VIP");
        vm.stopPrank();
        
        SubscriptionManager.CreatorTier[] memory tiers = manager.getCreatorTiers(creator);
        assertEq(tiers.length, 3);
        assertEq(tiers[0].price, TIER_PRICE);
        assertEq(tiers[1].price, 20 * 10**6);
        assertEq(tiers[2].price, 50 * 10**6);
    }
    
    function testPauseAndUnpause() public {
        manager.pause();

        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        manager.unpause();

        vm.startPrank(subscriber);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        assertTrue(manager.isSubscriptionActive(subscriber, creator));
    }
    
    function testSubscriberCount() public {
        assertEq(manager.subscriberCount(creator), 0);

        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        assertEq(manager.subscriberCount(creator), 1);

        vm.startPrank(subscriber2);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        assertEq(manager.subscriberCount(creator), 2);

        vm.prank(subscriber);
        manager.cancelSubscription(creator);

        assertEq(manager.subscriberCount(creator), 1);
    }

    // ============ Tier Management Tests ============

    function testUpdateTier() public {
        vm.startPrank(creator);

        // Update the tier
        manager.updateTier(0, 20 * 10**6, 60 days, true);

        (uint256 price, uint256 duration, string memory name, bool active) =
            manager.creatorTier(creator, 0);

        assertEq(price, 20 * 10**6);
        assertEq(duration, 60 days);
        assertEq(name, "Basic");
        assertTrue(active);
        vm.stopPrank();
    }

    function testUpdateTierDeactivate() public {
        vm.startPrank(creator);

        // Deactivate the tier
        manager.updateTier(0, 10 * 10**6, 30 days, false);

        (,,, bool active) = manager.creatorTier(creator, 0);
        assertFalse(active);
        vm.stopPrank();
    }

    function testCannotUpdateInvalidTier() public {
        vm.prank(creator);
        vm.expectRevert(SubscriptionManager.InvalidTier.selector);
        manager.updateTier(99, 10 * 10**6, 30 days, true);
    }

    function testCannotUpdateTierWithZeroPrice() public {
        vm.prank(creator);
        vm.expectRevert(SubscriptionManager.InvalidPrice.selector);
        manager.updateTier(0, 0, 30 days, true);
    }

    function testCannotUpdateTierWithZeroDuration() public {
        vm.prank(creator);
        vm.expectRevert(SubscriptionManager.InvalidDuration.selector);
        manager.updateTier(0, 10 * 10**6, 0, true);
    }

    function testCannotSubscribeToDeactivatedTier() public {
        // Deactivate tier
        vm.prank(creator);
        manager.updateTier(0, 10 * 10**6, 30 days, false);

        // Try to subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        vm.expectRevert(SubscriptionManager.InvalidTier.selector);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();
    }

    // ============ Subscription Expiry Tests ============

    function testSubscriptionExpiry() public {
        // Subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        // Check active before expiry
        assertTrue(manager.isSubscriptionActive(subscriber, creator));

        // Fast forward past expiry
        vm.warp(block.timestamp + TIER_DURATION + 1);

        // Check inactive after expiry
        assertFalse(manager.isSubscriptionActive(subscriber, creator));
    }

    function testCannotRenewInactiveSubscription() public {
        // Subscribe and cancel
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE * 2);
        manager.subscribe(creator, 0, false);
        manager.cancelSubscription(creator);

        // Try to renew
        vm.expectRevert(SubscriptionManager.NoActiveSubscription.selector);
        manager.renewSubscription(creator);
        vm.stopPrank();
    }

    function testRenewBeforeExpiry() public {
        // Subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE * 2);
        manager.subscribe(creator, 0, false);

        uint256 firstEndTime = block.timestamp + TIER_DURATION;

        // Renew immediately
        manager.renewSubscription(creator);
        vm.stopPrank();

        // End time should extend from original end time
        (,,,,,uint256 endTime,,,) = manager.subscriptions(1);
        assertEq(endTime, firstEndTime + TIER_DURATION);
    }

    function testCannotRenewToDeactivatedTier() public {
        // Subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE * 2);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        // Deactivate tier
        vm.prank(creator);
        manager.updateTier(0, 10 * 10**6, 30 days, false);

        // Try to renew
        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.InvalidTier.selector);
        manager.renewSubscription(creator);
    }

    // ============ Multiple Tier Tests ============

    function testMultipleTierSubscriptions() public {
        address creator2 = makeAddr("creator2");

        // Creator2 creates a tier
        vm.prank(creator2);
        manager.createTier(15 * 10**6, 60 days, "Premium");

        // Subscriber subscribes to both creators
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE + 15 * 10**6);

        manager.subscribe(creator, 0, false);
        manager.subscribe(creator2, 0, false);
        vm.stopPrank();

        // Check both subscriptions are active
        assertTrue(manager.isSubscriptionActive(subscriber, creator));
        assertTrue(manager.isSubscriptionActive(subscriber, creator2));
    }

    function testSubscribeToDifferentTierSameCreator() public {
        // Try to subscribe to the same creator again (should fail)
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE * 2);
        manager.subscribe(creator, 0, false);

        vm.expectRevert(SubscriptionManager.SubscriptionExists.selector);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();
    }

    function testResubscribeAfterCancel() public {
        // Subscribe and cancel
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE * 2);
        manager.subscribe(creator, 0, false);
        manager.cancelSubscription(creator);

        // Resubscribe should work
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        assertTrue(manager.isSubscriptionActive(subscriber, creator));
    }

    // ============ Fee Calculation Tests ============

    function testPlatformFeeCalculation() public {
        // Subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        uint256 platformFee = (TIER_PRICE * 300) / 10000; // 3%
        uint256 creatorAmount = TIER_PRICE - platformFee;

        assertEq(manager.creatorBalances(creator), creatorAmount);
        assertEq(manager.creatorBalances(owner), platformFee);
    }

    function testDifferentPlatformFeeOnSubscription() public {
        // Update platform fee to 5%
        manager.updatePlatformFee(500);

        // Subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        uint256 platformFee = (TIER_PRICE * 500) / 10000; // 5%
        uint256 creatorAmount = TIER_PRICE - platformFee;

        assertEq(manager.creatorBalances(creator), creatorAmount);
        assertEq(manager.creatorBalances(owner), platformFee);
    }

    function testPlatformFeeMaximum() public {
        // Set to maximum 10%
        manager.updatePlatformFee(1000);
        assertEq(manager.s_platformFeePercent(), 1000);
    }

    // ============ Withdrawal Tests ============

    function testMultipleWithdrawals() public {
        // Subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        uint256 platformFee = (TIER_PRICE * 300) / 10000;
        uint256 creatorAmount = TIER_PRICE - platformFee;

        // First withdrawal
        vm.prank(creator);
        manager.withdrawFunds();

        assertEq(manager.creatorBalances(creator), 0);

        // Subscribe again
        vm.startPrank(subscriber2);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        // Second withdrawal
        uint256 balanceBefore = usdc.balanceOf(creator);
        vm.prank(creator);
        manager.withdrawFunds();

        assertEq(usdc.balanceOf(creator) - balanceBefore, creatorAmount);
    }

    function testOwnerCanWithdrawPlatformFees() public {
        // Subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        uint256 platformFee = (TIER_PRICE * 300) / 10000;

        // Owner withdraws
        uint256 balanceBefore = usdc.balanceOf(owner);
        manager.withdrawFunds();

        assertEq(usdc.balanceOf(owner) - balanceBefore, platformFee);
    }

    // ============ View Function Tests ============

    function testGetSubscription() public {
        // Subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        uint256 subId = manager.subscribe(creator, 0, true);
        vm.stopPrank();

        SubscriptionManager.Subscription memory sub = manager.getSubscription(subId);

        assertEq(sub.id, 1);
        assertEq(sub.subscriber, subscriber);
        assertEq(sub.creator, creator);
        assertEq(sub.tier, 0);
        assertEq(sub.amount, TIER_PRICE);
        assertTrue(sub.isActive);
        assertTrue(sub.autoRenew);
    }

    function testGetTier() public {
        SubscriptionManager.CreatorTier memory tier = manager.getTier(creator, 0);

        assertEq(tier.price, TIER_PRICE);
        assertEq(tier.duration, TIER_DURATION);
        assertEq(tier.name, "Basic");
        assertTrue(tier.isActive);
    }

    function testGetCreatorTiersEmpty() public {
        address newCreator = makeAddr("newCreator");
        SubscriptionManager.CreatorTier[] memory tiers = manager.getCreatorTiers(newCreator);
        assertEq(tiers.length, 0);
    }

    // ============ Insufficient Balance Tests ============

    function testCannotSubscribeWithInsufficientBalance() public {
        address poorSubscriber = makeAddr("poorSubscriber");
        usdc.mint(poorSubscriber, 5 * 10**6); // Only $5

        vm.startPrank(poorSubscriber);
        usdc.approve(address(manager), TIER_PRICE);
        vm.expectRevert(); // Will revert due to insufficient balance in ERC20
        manager.subscribe(creator, 0, false);
        vm.stopPrank();
    }

    function testCannotSubscribeWithoutApproval() public {
        vm.prank(subscriber);
        vm.expectRevert(); // Will revert due to insufficient allowance
        manager.subscribe(creator, 0, false);
    }

    // ============ Auto-Renew Tests ============

    function testAutoRenewFlag() public {
        // Subscribe with auto-renew enabled
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, true);
        vm.stopPrank();

        (,,,,,,, , bool autoRenew) = manager.subscriptions(1);
        assertTrue(autoRenew);

        // Subscribe subscriber2 with auto-renew disabled
        vm.startPrank(subscriber2);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        (,,,,,,, , bool autoRenew2) = manager.subscriptions(2);
        assertFalse(autoRenew2);
    }

    function testCancelDisablesAutoRenew() public {
        // Subscribe with auto-renew
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, true);

        // Cancel
        manager.cancelSubscription(creator);
        vm.stopPrank();

        (,,,,,,, , bool autoRenew) = manager.subscriptions(1);
        assertFalse(autoRenew);
    }

    // ============ Admin Function Tests ============

    function testOnlyOwnerCanUpdatePlatformFee() public {
        vm.prank(subscriber);
        vm.expectRevert();
        manager.updatePlatformFee(400);
    }

    function testOnlyOwnerCanSetAccessPassNFT() public {
        address newNFT = makeAddr("newNFT");

        vm.prank(subscriber);
        vm.expectRevert();
        manager.setAccessPassNFT(newNFT);

        // Owner can set it
        manager.setAccessPassNFT(newNFT);
        assertEq(manager.s_accessPassNFT(), newNFT);
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(subscriber);
        vm.expectRevert();
        manager.pause();
    }

    function testOnlyOwnerCanUnpause() public {
        manager.pause();

        vm.prank(subscriber);
        vm.expectRevert();
        manager.unpause();
    }

    // ============ Event Emission Tests ============

    function testTierCreatedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit TierCreated(creator, 1, 20 * 10**6, 60 days, "Premium");

        vm.prank(creator);
        manager.createTier(20 * 10**6, 60 days, "Premium");
    }

    function testFundsWithdrawnEvent() public {
        // Subscribe first
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        manager.subscribe(creator, 0, false);
        vm.stopPrank();

        uint256 platformFee = (TIER_PRICE * 300) / 10000;
        uint256 creatorAmount = TIER_PRICE - platformFee;

        vm.expectEmit(true, false, false, true);
        emit FundsWithdrawn(creator, creatorAmount);

        vm.prank(creator);
        manager.withdrawFunds();
    }

    function testPlatformFeeUpdatedEvent() public {
        vm.expectEmit(false, false, false, true);
        emit PlatformFeeUpdated(500);

        manager.updatePlatformFee(500);
    }

    function testSubscriptionRenewedEvent() public {
        // Subscribe
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE * 2);
        manager.subscribe(creator, 0, false);

        uint256 firstEndTime = block.timestamp + TIER_DURATION;
        uint256 expectedEndTime = firstEndTime + TIER_DURATION;

        vm.expectEmit(true, false, false, true);
        emit SubscriptionRenewed(1, expectedEndTime);

        manager.renewSubscription(creator);
        vm.stopPrank();
    }

    // ============ Counter Tests ============

    function testSubscriptionCounterIncrement() public {
        assertEq(manager.s_subscriptionCounter(), 0);

        // First subscription
        vm.startPrank(subscriber);
        usdc.approve(address(manager), TIER_PRICE);
        uint256 subId1 = manager.subscribe(creator, 0, false);
        vm.stopPrank();

        assertEq(subId1, 1);
        assertEq(manager.s_subscriptionCounter(), 1);

        // Second subscription
        vm.startPrank(subscriber2);
        usdc.approve(address(manager), TIER_PRICE);
        uint256 subId2 = manager.subscribe(creator, 0, false);
        vm.stopPrank();

        assertEq(subId2, 2);
        assertEq(manager.s_subscriptionCounter(), 2);
    }

    function testCreatorTierCounterIncrement() public {
        assertEq(manager.creatorTierCount(creator), 1); // Already has 1 from setup

        vm.startPrank(creator);
        manager.createTier(20 * 10**6, 60 days, "Premium");
        assertEq(manager.creatorTierCount(creator), 2);

        manager.createTier(50 * 10**6, 365 days, "VIP");
        assertEq(manager.creatorTierCount(creator), 3);
        vm.stopPrank();
    }
}