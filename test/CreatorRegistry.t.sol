// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CreatorRegistry.sol";

contract CreatorRegistryTest is Test {
    CreatorRegistry public registry;

    address public owner;
    address public creator1;
    address public creator2;
    address public creator3;
    address public nonCreator;

    uint256 constant REGISTRATION_FEE = 0.01 ether;
    string constant NAME = "Test Creator";
    string constant METADATA_URI = "ipfs://QmTestCreator123";
    string[] socialLinks;

    event CreatorRegistered(address indexed creator, string name, string metadataURI);
    event CreatorVerified(address indexed creator);
    event CreatorUnverified(address indexed creator);
    event ProfileUpdated(address indexed creator, string metadataURI);
    event CreatorDeactivated(address indexed creator);
    event CreatorReactivated(address indexed creator);
    event StatsUpdated(address indexed creator, uint256 totalSubscribers, uint256 totalRevenue);

    function setUp() public {
        owner = address(this);
        creator1 = makeAddr("creator1");
        creator2 = makeAddr("creator2");
        creator3 = makeAddr("creator3");
        nonCreator = makeAddr("nonCreator");

        registry = new CreatorRegistry();

        // Fund creators
        vm.deal(creator1, 10 ether);
        vm.deal(creator2, 10 ether);
        vm.deal(creator3, 10 ether);

        // Setup social links
        socialLinks.push("https://twitter.com/testcreator");
        socialLinks.push("https://instagram.com/testcreator");
    }

    // ============ Constructor & Initialization Tests ============

    function testConstructor() public {
        assertEq(registry.owner(), owner);
        assertEq(registry.s_registrationFee(), REGISTRATION_FEE);
        assertEq(registry.s_creatorCount(), 0);
    }

    // ============ Creator Registration Tests ============

    function testRegisterCreator() public {
        vm.expectEmit(true, false, false, true);
        emit CreatorRegistered(creator1, NAME, METADATA_URI);

        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        assertTrue(registry.isRegistered(creator1));
        assertEq(registry.s_creatorCount(), 1);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.name, NAME);
        assertEq(profile.metadataURI, METADATA_URI);
        assertEq(profile.wallet, creator1);
        assertEq(profile.registrationTime, block.timestamp);
        assertFalse(profile.isVerified);
        assertTrue(profile.isActive);
        assertEq(profile.totalSubscribers, 0);
        assertEq(profile.totalRevenue, 0);
        assertEq(profile.socialLinks.length, 2);
    }

    function testRegisterMultipleCreators() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        vm.prank(creator2);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 2", METADATA_URI, socialLinks);

        vm.prank(creator3);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 3", METADATA_URI, socialLinks);

        assertEq(registry.s_creatorCount(), 3);
        assertTrue(registry.isRegistered(creator1));
        assertTrue(registry.isRegistered(creator2));
        assertTrue(registry.isRegistered(creator3));
    }

    function testCannotRegisterTwice() public {
        vm.startPrank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        vm.expectRevert(CreatorRegistry.AlreadyRegistered.selector);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);
        vm.stopPrank();
    }

    function testCannotRegisterWithInsufficientFee() public {
        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.InsufficientFee.selector);
        registry.registerCreator{value: 0.005 ether}(NAME, METADATA_URI, socialLinks);
    }

    function testCanRegisterWithExcessFee() public {
        uint256 balanceBefore = creator1.balance;

        vm.prank(creator1);
        registry.registerCreator{value: 0.02 ether}(NAME, METADATA_URI, socialLinks);

        assertTrue(registry.isRegistered(creator1));
        assertEq(balanceBefore - creator1.balance, 0.02 ether);
    }

    function testRegisterWithEmptySocialLinks() public {
        string[] memory emptySocialLinks = new string[](0);

        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, emptySocialLinks);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.socialLinks.length, 0);
    }

    function testCannotRegisterWhenPaused() public {
        registry.pause();

        vm.prank(creator1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);
    }

    // ============ Profile Update Tests ============

    function testUpdateProfile() public {
        vm.startPrank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        string memory newMetadataURI = "ipfs://QmNewMetadata456";
        string[] memory newSocialLinks = new string[](1);
        newSocialLinks[0] = "https://youtube.com/testcreator";

        vm.expectEmit(true, false, false, true);
        emit ProfileUpdated(creator1, newMetadataURI);

        registry.updateProfile(newMetadataURI, newSocialLinks);
        vm.stopPrank();

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.metadataURI, newMetadataURI);
        assertEq(profile.socialLinks.length, 1);
        assertEq(profile.socialLinks[0], "https://youtube.com/testcreator");
    }

    function testCannotUpdateProfileIfNotRegistered() public {
        vm.prank(nonCreator);
        vm.expectRevert(CreatorRegistry.NotRegistered.selector);
        registry.updateProfile(METADATA_URI, socialLinks);
    }

    // ============ Profile Activation Tests ============

    function testDeactivateProfile() public {
        vm.startPrank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        vm.expectEmit(true, false, false, false);
        emit CreatorDeactivated(creator1);

        registry.deactivateProfile();
        vm.stopPrank();

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertFalse(profile.isActive);
    }

    function testReactivateProfile() public {
        vm.startPrank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);
        registry.deactivateProfile();

        vm.expectEmit(true, false, false, false);
        emit CreatorReactivated(creator1);

        registry.reactivateProfile();
        vm.stopPrank();

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertTrue(profile.isActive);
    }

    function testCannotDeactivateIfNotRegistered() public {
        vm.prank(nonCreator);
        vm.expectRevert(CreatorRegistry.NotRegistered.selector);
        registry.deactivateProfile();
    }

    function testCannotReactivateIfNotRegistered() public {
        vm.prank(nonCreator);
        vm.expectRevert(CreatorRegistry.NotRegistered.selector);
        registry.reactivateProfile();
    }

    function testDeactivateThenReactivate() public {
        vm.startPrank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        registry.deactivateProfile();
        assertFalse(registry.getCreatorProfile(creator1).isActive);

        registry.reactivateProfile();
        assertTrue(registry.getCreatorProfile(creator1).isActive);

        vm.stopPrank();
    }

    // ============ Stats Update Tests ============

    function testUpdateCreatorStatsIncrement() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        vm.expectEmit(true, false, false, true);
        emit StatsUpdated(creator1, 5, 1000);

        registry.updateCreatorStats(creator1, 5, 1000, true);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.totalSubscribers, 5);
        assertEq(profile.totalRevenue, 1000);
    }

    function testUpdateCreatorStatsDecrement() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        // Increment first
        registry.updateCreatorStats(creator1, 10, 2000, true);

        // Decrement
        registry.updateCreatorStats(creator1, 3, 0, false);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.totalSubscribers, 7);
        assertEq(profile.totalRevenue, 2000); // Revenue stays same on decrement
    }

    function testUpdateCreatorStatsMultipleTimes() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        registry.updateCreatorStats(creator1, 5, 500, true);
        registry.updateCreatorStats(creator1, 3, 300, true);
        registry.updateCreatorStats(creator1, 2, 200, true);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.totalSubscribers, 10);
        assertEq(profile.totalRevenue, 1000);
    }

    function testCannotUpdateStatsForUnregisteredCreator() public {
        vm.expectRevert(CreatorRegistry.NotRegistered.selector);
        registry.updateCreatorStats(nonCreator, 5, 1000, true);
    }

    // ============ View Function Tests ============

    function testGetCreatorProfile() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);

        assertEq(profile.name, NAME);
        assertEq(profile.metadataURI, METADATA_URI);
        assertEq(profile.wallet, creator1);
        assertFalse(profile.isVerified);
        assertTrue(profile.isActive);
    }

    function testGetAllCreators() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 1", METADATA_URI, socialLinks);

        vm.prank(creator2);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 2", METADATA_URI, socialLinks);

        address[] memory allCreators = registry.getAllCreators();
        assertEq(allCreators.length, 2);
        assertEq(allCreators[0], creator1);
        assertEq(allCreators[1], creator2);
    }

    function testGetActiveCreators() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 1", METADATA_URI, socialLinks);

        vm.prank(creator2);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 2", METADATA_URI, socialLinks);

        vm.prank(creator3);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 3", METADATA_URI, socialLinks);

        // Deactivate creator2
        vm.prank(creator2);
        registry.deactivateProfile();

        address[] memory activeCreators = registry.getActiveCreators();
        assertEq(activeCreators.length, 2);
        assertEq(activeCreators[0], creator1);
        assertEq(activeCreators[1], creator3);
    }

    function testGetActiveCreatorsEmpty() public {
        address[] memory activeCreators = registry.getActiveCreators();
        assertEq(activeCreators.length, 0);
    }

    function testGetVerifiedCreators() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 1", METADATA_URI, socialLinks);

        vm.prank(creator2);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 2", METADATA_URI, socialLinks);

        vm.prank(creator3);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 3", METADATA_URI, socialLinks);

        // Verify creator1 and creator3
        registry.verifyCreator(creator1);
        registry.verifyCreator(creator3);

        address[] memory verifiedCreators = registry.getVerifiedCreators();
        assertEq(verifiedCreators.length, 2);
        assertEq(verifiedCreators[0], creator1);
        assertEq(verifiedCreators[1], creator3);
    }

    function testGetVerifiedCreatorsFiltersInactive() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 1", METADATA_URI, socialLinks);

        vm.prank(creator2);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 2", METADATA_URI, socialLinks);

        // Verify both
        registry.verifyCreator(creator1);
        registry.verifyCreator(creator2);

        // Deactivate creator1
        vm.prank(creator1);
        registry.deactivateProfile();

        address[] memory verifiedCreators = registry.getVerifiedCreators();
        assertEq(verifiedCreators.length, 1);
        assertEq(verifiedCreators[0], creator2);
    }

    function testGetVerifiedCreatorsEmpty() public {
        address[] memory verifiedCreators = registry.getVerifiedCreators();
        assertEq(verifiedCreators.length, 0);
    }

    function testGetCreatorByAddress() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        registry.updateCreatorStats(creator1, 10, 5000, true);

        (string memory name, string memory metadataURI, bool verified, bool active, uint256 totalSubscribers) =
            registry.getCreatorByAddress(creator1);

        assertEq(name, NAME);
        assertEq(metadataURI, METADATA_URI);
        assertFalse(verified);
        assertTrue(active);
        assertEq(totalSubscribers, 10);
    }

    // ============ Admin - Verification Tests ============

    function testVerifyCreator() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        vm.expectEmit(true, false, false, false);
        emit CreatorVerified(creator1);

        registry.verifyCreator(creator1);

        assertTrue(registry.isVerified(creator1));
        assertTrue(registry.getCreatorProfile(creator1).isVerified);
    }

    function testUnverifyCreator() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        registry.verifyCreator(creator1);
        assertTrue(registry.isVerified(creator1));

        vm.expectEmit(true, false, false, false);
        emit CreatorUnverified(creator1);

        registry.unverifyCreator(creator1);

        assertFalse(registry.isVerified(creator1));
        assertFalse(registry.getCreatorProfile(creator1).isVerified);
    }

    function testCannotVerifyUnregisteredCreator() public {
        vm.expectRevert(CreatorRegistry.NotRegistered.selector);
        registry.verifyCreator(nonCreator);
    }

    function testCannotUnverifyUnregisteredCreator() public {
        vm.expectRevert(CreatorRegistry.NotRegistered.selector);
        registry.unverifyCreator(nonCreator);
    }

    function testOnlyOwnerCanVerify() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        vm.prank(nonCreator);
        vm.expectRevert();
        registry.verifyCreator(creator1);
    }

    function testOnlyOwnerCanUnverify() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        registry.verifyCreator(creator1);

        vm.prank(nonCreator);
        vm.expectRevert();
        registry.unverifyCreator(creator1);
    }

    // ============ Admin - Fee Management Tests ============

    function testUpdateRegistrationFee() public {
        uint256 newFee = 0.05 ether;
        registry.updateRegistrationFee(newFee);

        assertEq(registry.s_registrationFee(), newFee);
    }

    function testUpdateRegistrationFeeToZero() public {
        registry.updateRegistrationFee(0);
        assertEq(registry.s_registrationFee(), 0);

        // Can register with zero fee
        vm.prank(creator1);
        registry.registerCreator{value: 0}(NAME, METADATA_URI, socialLinks);

        assertTrue(registry.isRegistered(creator1));
    }

    function testOnlyOwnerCanUpdateRegistrationFee() public {
        vm.prank(nonCreator);
        vm.expectRevert();
        registry.updateRegistrationFee(0.05 ether);
    }

    function testWithdrawFees() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        vm.prank(creator2);
        registry.registerCreator{value: REGISTRATION_FEE}("Creator 2", METADATA_URI, socialLinks);

        uint256 balanceBefore = owner.balance;
        registry.withdrawFees();
        uint256 balanceAfter = owner.balance;

        assertEq(balanceAfter - balanceBefore, REGISTRATION_FEE * 2);
        assertEq(address(registry).balance, 0);
    }

    function testWithdrawFeesWithZeroBalance() public {
        uint256 balanceBefore = owner.balance;
        registry.withdrawFees();
        uint256 balanceAfter = owner.balance;

        assertEq(balanceAfter, balanceBefore);
    }

    function testOnlyOwnerCanWithdrawFees() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        vm.prank(nonCreator);
        vm.expectRevert();
        registry.withdrawFees();
    }

    // ============ Admin - Pause Tests ============

    function testPause() public {
        registry.pause();
        assertTrue(registry.paused());
    }

    function testUnpause() public {
        registry.pause();
        registry.unpause();
        assertFalse(registry.paused());
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(nonCreator);
        vm.expectRevert();
        registry.pause();
    }

    function testOnlyOwnerCanUnpause() public {
        registry.pause();

        vm.prank(nonCreator);
        vm.expectRevert();
        registry.unpause();
    }

    function testCannotRegisterWhenPausedUnpauseWorks() public {
        registry.pause();

        vm.prank(creator1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        registry.unpause();

        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        assertTrue(registry.isRegistered(creator1));
    }

    // ============ Edge Cases ============

    function testRegisterWithVeryLongName() public {
        string memory longName = "This is a very long creator name that exceeds normal expectations for testing purposes";

        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(longName, METADATA_URI, socialLinks);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.name, longName);
    }

    function testRegisterWithEmptyName() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}("", METADATA_URI, socialLinks);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.name, "");
    }

    function testRegisterWithManySocialLinks() public {
        string[] memory manySocialLinks = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            manySocialLinks[i] = string(abi.encodePacked("https://social", vm.toString(i), ".com"));
        }

        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, manySocialLinks);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.socialLinks.length, 10);
    }

    function testUpdateProfileEmptyArrays() public {
        vm.startPrank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        string[] memory emptySocialLinks = new string[](0);
        registry.updateProfile("", emptySocialLinks);

        vm.stopPrank();

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.metadataURI, "");
        assertEq(profile.socialLinks.length, 0);
    }

    function testMultipleStatsUpdates() public {
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        // Increment
        registry.updateCreatorStats(creator1, 10, 1000, true);
        registry.updateCreatorStats(creator1, 5, 500, true);

        // Decrement
        registry.updateCreatorStats(creator1, 3, 0, false);

        // Increment again
        registry.updateCreatorStats(creator1, 2, 200, true);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.totalSubscribers, 14); // 10 + 5 - 3 + 2
        assertEq(profile.totalRevenue, 1700); // 1000 + 500 + 200
    }

    function testGetCreatorProfileUnregistered() public {
        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(nonCreator);

        assertEq(profile.name, "");
        assertEq(profile.metadataURI, "");
        assertEq(profile.wallet, address(0));
        assertEq(profile.registrationTime, 0);
        assertFalse(profile.isVerified);
        assertFalse(profile.isActive);
        assertEq(profile.totalSubscribers, 0);
        assertEq(profile.totalRevenue, 0);
    }

    // ============ Integration Tests ============

    function testCompleteCreatorLifecycle() public {
        // Register
        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        // Verify
        registry.verifyCreator(creator1);
        assertTrue(registry.isVerified(creator1));

        // Update stats
        registry.updateCreatorStats(creator1, 100, 50000, true);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.totalSubscribers, 100);
        assertEq(profile.totalRevenue, 50000);

        // Update profile
        string[] memory newLinks = new string[](1);
        newLinks[0] = "https://newlink.com";
        vm.prank(creator1);
        registry.updateProfile("ipfs://newURI", newLinks);

        // Deactivate
        vm.prank(creator1);
        registry.deactivateProfile();
        assertFalse(registry.getCreatorProfile(creator1).isActive);

        // Reactivate
        vm.prank(creator1);
        registry.reactivateProfile();
        assertTrue(registry.getCreatorProfile(creator1).isActive);

        // Unverify
        registry.unverifyCreator(creator1);
        assertFalse(registry.isVerified(creator1));
    }

    // ============ Fuzz Tests ============

    function testFuzzRegisterCreator(address _creator, string memory _name, uint256 _fee) public {
        vm.assume(_creator != address(0));
        vm.assume(_fee >= REGISTRATION_FEE);
        vm.assume(_fee < 100 ether);

        vm.deal(_creator, _fee);

        vm.prank(_creator);
        registry.registerCreator{value: _fee}(_name, METADATA_URI, socialLinks);

        assertTrue(registry.isRegistered(_creator));
        assertEq(registry.getCreatorProfile(_creator).name, _name);
    }

    function testFuzzUpdateCreatorStats(uint256 _subscribers, uint256 _revenue) public {
        vm.assume(_subscribers < type(uint128).max);
        vm.assume(_revenue < type(uint128).max);

        vm.prank(creator1);
        registry.registerCreator{value: REGISTRATION_FEE}(NAME, METADATA_URI, socialLinks);

        registry.updateCreatorStats(creator1, _subscribers, _revenue, true);

        CreatorRegistry.CreatorProfile memory profile = registry.getCreatorProfile(creator1);
        assertEq(profile.totalSubscribers, _subscribers);
        assertEq(profile.totalRevenue, _revenue);
    }

    function testFuzzUpdateRegistrationFee(uint256 _newFee) public {
        vm.assume(_newFee < 10 ether);

        registry.updateRegistrationFee(_newFee);
        assertEq(registry.s_registrationFee(), _newFee);
    }
}
