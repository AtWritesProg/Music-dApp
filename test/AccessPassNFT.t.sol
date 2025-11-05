// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AccessPassNFT.sol";

contract AccessPassNFTTest is Test {
    AccessPassNFT public nft;

    address public owner;
    address public minter;
    address public subscriber;
    address public subscriber2;
    address public creator;
    address public creator2;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    uint256 constant TIER = 0;
    uint256 constant DURATION = 30 days;
    string constant METADATA_URI = "ipfs://QmTest123";

    event PassMinted(
        uint256 indexed tokenId,
        address indexed subscriber,
        address indexed creator,
        uint256 expiryTime
    );

    event PassExpired(
        uint256 indexed tokenId,
        address indexed subscriber,
        address indexed creator
    );

    event PassRenewed(
        uint256 indexed tokenId,
        uint256 newExpiryTime
    );

    function setUp() public {
        owner = address(this);
        minter = makeAddr("minter");
        subscriber = makeAddr("subscriber");
        subscriber2 = makeAddr("subscriber2");
        creator = makeAddr("creator");
        creator2 = makeAddr("creator2");

        nft = new AccessPassNFT();
        nft.grantRole(MINTER_ROLE, minter);
    }

    // ============ Constructor & Initialization Tests ============

    function testConstructor() public {
        assertEq(nft.name(), "Subify Access Pass");
        assertEq(nft.symbol(), "SPASS");
        assertTrue(nft.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertTrue(nft.hasRole(MINTER_ROLE, owner));
    }

    // ============ Mint Pass Tests ============

    function testMintPass() public {
        vm.prank(minter);
        uint256 expectedExpiry = block.timestamp + DURATION;

        vm.expectEmit(true, true, true, true);
        emit PassMinted(0, subscriber, creator, expectedExpiry);

        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(tokenId), subscriber);
        assertEq(nft.tokenURI(tokenId), METADATA_URI);

        // Check metadata
        AccessPassNFT.PassMetadata memory metadata = nft.getPassMetadata(tokenId);
        assertEq(metadata.creator, creator);
        assertEq(metadata.subscriber, subscriber);
        assertEq(metadata.tier, TIER);
        assertEq(metadata.mintTime, block.timestamp);
        assertEq(metadata.expiryTime, expectedExpiry);
        assertTrue(metadata.active);

        // Check mappings
        assertEq(nft.userPasses(subscriber, creator), tokenId);
    }

    function testMintMultiplePasses() public {
        vm.startPrank(minter);

        // Mint pass for subscriber1 -> creator1
        uint256 tokenId1 = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        assertEq(tokenId1, 0);

        // Mint pass for subscriber2 -> creator1
        uint256 tokenId2 = nft.mintPass(subscriber2, creator, TIER, DURATION, METADATA_URI);
        assertEq(tokenId2, 1);

        // Mint pass for subscriber1 -> creator2
        uint256 tokenId3 = nft.mintPass(subscriber, creator2, TIER, DURATION, METADATA_URI);
        assertEq(tokenId3, 2);

        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId1), subscriber);
        assertEq(nft.ownerOf(tokenId2), subscriber2);
        assertEq(nft.ownerOf(tokenId3), subscriber);
    }

    function testCannotMintPassWhenActivePassExists() public {
        vm.startPrank(minter);

        // Mint first pass
        nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        // Try to mint duplicate pass
        vm.expectRevert(AccessPassNFT.PassExists.selector);
        nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        vm.stopPrank();
    }

    function testCanMintPassAfterExpiration() public {
        vm.startPrank(minter);

        // Mint first pass
        uint256 tokenId1 = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        // Expire the pass
        nft.expirePass(tokenId1);

        // Now can mint a new pass
        uint256 tokenId2 = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        assertEq(tokenId2, 1);

        vm.stopPrank();
    }

    function testOnlyMinterCanMintPass() public {
        vm.prank(subscriber);
        vm.expectRevert();
        nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
    }

    // ============ Renew Pass Tests ============

    function testRenewPass() public {
        vm.startPrank(minter);

        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        uint256 originalExpiry = block.timestamp + DURATION;

        // Renew pass
        uint256 additionalDuration = 15 days;
        uint256 expectedExpiry = originalExpiry + additionalDuration;

        vm.expectEmit(true, false, false, true);
        emit PassRenewed(tokenId, expectedExpiry);

        nft.renewPass(tokenId, additionalDuration);

        vm.stopPrank();

        AccessPassNFT.PassMetadata memory metadata = nft.getPassMetadata(tokenId);
        assertEq(metadata.expiryTime, expectedExpiry);
    }

    function testRenewPassAfterExpiry() public {
        vm.startPrank(minter);

        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        // Fast forward past expiry
        vm.warp(block.timestamp + DURATION + 1 days);

        // Renew should extend from current time
        uint256 additionalDuration = 30 days;
        nft.renewPass(tokenId, additionalDuration);

        vm.stopPrank();

        AccessPassNFT.PassMetadata memory metadata = nft.getPassMetadata(tokenId);
        assertEq(metadata.expiryTime, block.timestamp + additionalDuration);
    }

    function testCannotRenewInactivePass() public {
        vm.startPrank(minter);

        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        // Expire the pass
        nft.expirePass(tokenId);

        // Try to renew
        vm.expectRevert(AccessPassNFT.PassesExpired.selector);
        nft.renewPass(tokenId, 30 days);

        vm.stopPrank();
    }

    function testOnlyMinterCanRenewPass() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        vm.prank(subscriber);
        vm.expectRevert();
        nft.renewPass(tokenId, 15 days);
    }

    // ============ Expire Pass Tests ============

    function testExpirePass() public {
        vm.startPrank(minter);

        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        vm.expectEmit(true, true, true, false);
        emit PassExpired(tokenId, subscriber, creator);

        nft.expirePass(tokenId);

        vm.stopPrank();

        AccessPassNFT.PassMetadata memory metadata = nft.getPassMetadata(tokenId);
        assertFalse(metadata.active);
        assertEq(nft.userPasses(subscriber, creator), 0);
    }

    function testExpireAlreadyExpiredPass() public {
        vm.startPrank(minter);

        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        nft.expirePass(tokenId);

        // Expiring again should not revert
        nft.expirePass(tokenId);

        vm.stopPrank();
    }

    function testOnlyMinterCanExpirePass() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        vm.prank(subscriber);
        vm.expectRevert();
        nft.expirePass(tokenId);
    }

    // ============ View Function Tests ============

    function testIsPassValid() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        // Should be valid initially
        assertTrue(nft.isPassValid(tokenId));

        // Should be valid before expiry
        vm.warp(block.timestamp + DURATION - 1);
        assertTrue(nft.isPassValid(tokenId));

        // Should be invalid after expiry
        vm.warp(block.timestamp + 2);
        assertFalse(nft.isPassValid(tokenId));
    }

    function testIsPassValidWhenInactive() public {
        vm.startPrank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        nft.expirePass(tokenId);
        vm.stopPrank();

        assertFalse(nft.isPassValid(tokenId));
    }

    function testVerifyAccess() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        (bool valid, uint256 returnedTokenId) = nft.verifyAccess(subscriber, creator);
        assertTrue(valid);
        assertEq(returnedTokenId, tokenId);
    }

    function testVerifyAccessNoPass() public {
        (bool valid, uint256 tokenId) = nft.verifyAccess(subscriber, creator);
        assertFalse(valid);
        assertEq(tokenId, 0);
    }

    function testVerifyAccessExpired() public {
        vm.prank(minter);
        nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        // Fast forward past expiry
        vm.warp(block.timestamp + DURATION + 1);

        (bool valid,) = nft.verifyAccess(subscriber, creator);
        assertFalse(valid);
    }

    function testGetTimeRemaining() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        assertEq(nft.getTimeRemaining(tokenId), DURATION);

        // Fast forward 15 days
        vm.warp(block.timestamp + 15 days);
        assertEq(nft.getTimeRemaining(tokenId), DURATION - 15 days);

        // Fast forward past expiry
        vm.warp(block.timestamp + DURATION);
        assertEq(nft.getTimeRemaining(tokenId), 0);
    }

    function testGetTimeRemainingInactive() public {
        vm.startPrank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        nft.expirePass(tokenId);
        vm.stopPrank();

        assertEq(nft.getTimeRemaining(tokenId), 0);
    }

    function testGetCreatorActivePasses() public {
        vm.startPrank(minter);

        // Mint 3 passes for the same creator
        uint256 tokenId1 = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        uint256 tokenId2 = nft.mintPass(subscriber2, creator, TIER, DURATION, METADATA_URI);

        // Mint pass for different creator
        nft.mintPass(subscriber, creator2, TIER, DURATION, METADATA_URI);

        vm.stopPrank();

        uint256[] memory activePasses = nft.getCreatorActivePasses(creator);
        assertEq(activePasses.length, 2);
        assertEq(activePasses[0], tokenId1);
        assertEq(activePasses[1], tokenId2);
    }

    function testGetCreatorActivePassesFiltersExpired() public {
        vm.startPrank(minter);

        uint256 tokenId1 = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        uint256 tokenId2 = nft.mintPass(subscriber2, creator, TIER, 60 days, METADATA_URI);

        vm.stopPrank();

        // Fast forward to expire first pass
        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory activePasses = nft.getCreatorActivePasses(creator);
        assertEq(activePasses.length, 1);
        assertEq(activePasses[0], tokenId2);
    }

    function testGetCreatorActivePassesFiltersInactive() public {
        vm.startPrank(minter);

        uint256 tokenId1 = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        nft.mintPass(subscriber2, creator, TIER, DURATION, METADATA_URI);

        // Expire first pass
        nft.expirePass(tokenId1);

        vm.stopPrank();

        uint256[] memory activePasses = nft.getCreatorActivePasses(creator);
        assertEq(activePasses.length, 1);
    }

    function testGetCreatorActivePassesEmpty() public {
        uint256[] memory activePasses = nft.getCreatorActivePasses(creator);
        assertEq(activePasses.length, 0);
    }

    // ============ Soul-Bound Tests ============

    function testCannotTransferPass() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        vm.prank(subscriber);
        vm.expectRevert(AccessPassNFT.SoulBoundToken.selector);
        nft.transferFrom(subscriber, subscriber2, tokenId);
    }

    function testCannotSafeTransferPass() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        vm.prank(subscriber);
        vm.expectRevert(AccessPassNFT.SoulBoundToken.selector);
        nft.safeTransferFrom(subscriber, subscriber2, tokenId);
    }

    function testCannotApproveTransfer() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        vm.prank(subscriber);
        vm.expectRevert(AccessPassNFT.SoulBoundToken.selector);
        nft.approve(subscriber2, tokenId);
    }

    function testCanBurnPass() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        vm.prank(subscriber);
        nft.burn(tokenId);

        // Token should no longer exist
        vm.expectRevert();
        nft.ownerOf(tokenId);
    }

    // ============ Access Control Tests ============

    function testGrantMinterRole() public {
        address newMinter = makeAddr("newMinter");

        nft.grantRole(MINTER_ROLE, newMinter);
        assertTrue(nft.hasRole(MINTER_ROLE, newMinter));

        // New minter can mint
        vm.prank(newMinter);
        nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
    }

    function testRevokeMinterRole() public {
        nft.revokeRole(MINTER_ROLE, minter);
        assertFalse(nft.hasRole(MINTER_ROLE, minter));

        // Revoked minter cannot mint
        vm.prank(minter);
        vm.expectRevert();
        nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
    }

    function testOnlyAdminCanGrantRoles() public {
        vm.prank(subscriber);
        vm.expectRevert();
        nft.grantRole(MINTER_ROLE, subscriber2);
    }

    function testOnlyAdminCanRevokeRoles() public {
        vm.prank(subscriber);
        vm.expectRevert();
        nft.revokeRole(MINTER_ROLE, minter);
    }

    // ============ ERC721 Standard Tests ============

    function testBalanceOf() public {
        assertEq(nft.balanceOf(subscriber), 0);

        vm.startPrank(minter);
        nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        assertEq(nft.balanceOf(subscriber), 1);

        nft.mintPass(subscriber, creator2, TIER, DURATION, METADATA_URI);
        assertEq(nft.balanceOf(subscriber), 2);
        vm.stopPrank();
    }

    function testOwnerOf() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        assertEq(nft.ownerOf(tokenId), subscriber);
    }

    function testTokenURI() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);

        assertEq(nft.tokenURI(tokenId), METADATA_URI);
    }

    function testSupportsInterface() public {
        // ERC721
        assertTrue(nft.supportsInterface(0x80ac58cd));
        // ERC721Metadata
        assertTrue(nft.supportsInterface(0x5b5e139f));
        // AccessControl
        assertTrue(nft.supportsInterface(0x7965db0b));
    }

    // ============ Edge Cases ============

    function testMintPassWithZeroDuration() public {
        vm.prank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, 0, METADATA_URI);

        // Pass should be immediately expired
        assertFalse(nft.isPassValid(tokenId));
    }

    function testMintPassWithLongDuration() public {
        vm.prank(minter);
        uint256 longDuration = 365 days * 10; // 10 years
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, longDuration, METADATA_URI);

        AccessPassNFT.PassMetadata memory metadata = nft.getPassMetadata(tokenId);
        assertEq(metadata.expiryTime, block.timestamp + longDuration);
    }

    function testRenewPassMultipleTimes() public {
        vm.startPrank(minter);

        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        uint256 originalExpiry = block.timestamp + DURATION;

        // Renew 3 times
        nft.renewPass(tokenId, 15 days);
        nft.renewPass(tokenId, 15 days);
        nft.renewPass(tokenId, 15 days);

        vm.stopPrank();

        AccessPassNFT.PassMetadata memory metadata = nft.getPassMetadata(tokenId);
        assertEq(metadata.expiryTime, originalExpiry + 45 days);
    }

    function testGetPassMetadataForNonexistentToken() public {
        AccessPassNFT.PassMetadata memory metadata = nft.getPassMetadata(999);

        assertEq(metadata.creator, address(0));
        assertEq(metadata.subscriber, address(0));
        assertEq(metadata.tier, 0);
        assertEq(metadata.mintTime, 0);
        assertEq(metadata.expiryTime, 0);
        assertFalse(metadata.active);
    }

    function testVerifyAccessForDifferentCreators() public {
        vm.startPrank(minter);

        nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        nft.mintPass(subscriber, creator2, TIER, DURATION, METADATA_URI);

        vm.stopPrank();

        (bool valid1,) = nft.verifyAccess(subscriber, creator);
        (bool valid2,) = nft.verifyAccess(subscriber, creator2);

        assertTrue(valid1);
        assertTrue(valid2);
    }

    // ============ Fuzz Tests ============

    function testFuzzMintPass(address _subscriber, address _creator, uint256 _tier, uint256 _duration) public {
        vm.assume(_subscriber != address(0));
        vm.assume(_creator != address(0));
        vm.assume(_duration > 0 && _duration < 365 days * 100);

        vm.prank(minter);
        uint256 tokenId = nft.mintPass(_subscriber, _creator, _tier, _duration, METADATA_URI);

        assertEq(nft.ownerOf(tokenId), _subscriber);

        AccessPassNFT.PassMetadata memory metadata = nft.getPassMetadata(tokenId);
        assertEq(metadata.subscriber, _subscriber);
        assertEq(metadata.creator, _creator);
        assertEq(metadata.tier, _tier);
    }

    function testFuzzRenewPass(uint256 _additionalDuration) public {
        vm.assume(_additionalDuration > 0 && _additionalDuration < 365 days * 100);

        vm.startPrank(minter);
        uint256 tokenId = nft.mintPass(subscriber, creator, TIER, DURATION, METADATA_URI);
        uint256 originalExpiry = block.timestamp + DURATION;

        nft.renewPass(tokenId, _additionalDuration);
        vm.stopPrank();

        AccessPassNFT.PassMetadata memory metadata = nft.getPassMetadata(tokenId);
        assertEq(metadata.expiryTime, originalExpiry + _additionalDuration);
    }
}
