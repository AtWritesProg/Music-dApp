//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AccessPassNFT
 * @notice ERC721 NFT representing access passes for music creators
 * @dev Inherits from ERC721, ERC721URIStorage, ERC721Burnable, and AccessControl
 * Soul-bound tokens representing access passes that cannot be transferred
 */

contract AccessPassNFT is ERC721, ERC721Burnable , ERC721URIStorage, AccessControl {

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 private p_tokenIdCounter;

    //============Structs==============

    struct PassMetadata {
        address creator;
        address subscriber;
        uint256 tier;
        uint256 mintTime;
        uint256 expiryTime;
        bool active;
    }

    //============Mappings=============

    //tokenId => PassMetadata
    mapping(uint256 => PassMetadata) public passMetadata;

    // subscriber => creator => tokenId
    mapping(address => mapping(address => uint256)) public userPasses;

    // creator => array of active pass tokenIds
    mapping(address => uint256[]) public creatorPasses;

    //===========Events============

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
    //============Error============

    error PassExists();
    error PassesExpired();

    //============Constructor=============

    constructor() ERC721("Subify Access Pass", "SPASS") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    //==========Core Function============

    /**
     * @notice Mint a new access pass NFT
     * @param subscriber Address receiving the pass
     * @param creator Address of creator
     * @param tier Subscription tier
     * @param duration Duration in seconds
     * @param metadataURI IPFS URI for token metadata
     */
    function mintPass(
        address subscriber,
        address creator,
        uint256 tier,
        uint256 duration,
        string memory metadataURI
    ) external onlyRole(MINTER_ROLE) returns (uint256) {
        // Check if user already has a pass for this creator
        uint256 existingTokenId = userPasses[subscriber][creator];
        if (existingTokenId != 0 && passMetadata[existingTokenId].active) {
            revert PassExists();
        }
        
        uint256 tokenId = p_tokenIdCounter;
        unchecked {
           p_tokenIdCounter++;
        }
        
        uint256 expiryTime = block.timestamp + duration;
        
        // Mint NFT
        _safeMint(subscriber, tokenId);
        _setTokenURI(tokenId, metadataURI);
        
        // Store metadata
        passMetadata[tokenId] = PassMetadata({
            creator: creator,
            subscriber: subscriber,
            tier: tier,
            mintTime: block.timestamp,
            expiryTime: expiryTime,
            active: true
        });
        
        // Update mappings
        userPasses[subscriber][creator] = tokenId;
        creatorPasses[creator].push(tokenId);
        
        emit PassMinted(tokenId, subscriber, creator, expiryTime);
        
        return tokenId;
    }

    /**
     * @notice Extend the expiry time of an existing pass
     * @param tokenId Token ID to renew
     * @param additionalDuration Additional time in seconds
     */
    function renewPass(
        uint256 tokenId,
        uint256 additionalDuration
    ) external onlyRole(MINTER_ROLE) {
        PassMetadata storage metadata = passMetadata[tokenId];
        
        if (!metadata.active) revert PassesExpired();
        
        // Extend from current expiry or now (whichever is later)
        uint256 newExpiry = block.timestamp > metadata.expiryTime
            ? block.timestamp + additionalDuration
            : metadata.expiryTime + additionalDuration;
        
        metadata.expiryTime = newExpiry;
        
        emit PassRenewed(tokenId, newExpiry);
    }

    /**
     * @notice Deactivate an expired or cancelled pass
     * @param tokenId Token ID to expire
     */
    function expirePass(uint256 tokenId) external onlyRole(MINTER_ROLE) {
        PassMetadata storage metadata = passMetadata[tokenId];
        
        if (!metadata.active) return;
        
        metadata.active = false;
        delete userPasses[metadata.subscriber][metadata.creator];
        
        emit PassExpired(tokenId, metadata.subscriber, metadata.creator);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Check if a pass is currently valid
     * @param tokenId Token ID to check
     */
    function isPassValid(uint256 tokenId) public view returns (bool) {
        PassMetadata memory metadata = passMetadata[tokenId];
        return metadata.active && block.timestamp <= metadata.expiryTime;
    }
    
    /**
     * @notice Verify if a user has valid access to a creator's content
     * @param subscriber Address of the subscriber
     * @param creator Address of the creator
     */
    function verifyAccess(
        address subscriber,
        address creator
    ) external view returns (bool, uint256) {
        uint256 tokenId = userPasses[subscriber][creator];
        
        if (tokenId == 0) return (false, 0);
        
        bool valid = isPassValid(tokenId);
        return (valid, tokenId);
    }
    
    /**
     * @notice Get pass metadata
     */
    function getPassMetadata(uint256 tokenId) 
        external 
        view 
        returns (PassMetadata memory) 
    {
        return passMetadata[tokenId];
    }
    
    /**
     * @notice Get time remaining on a pass
     */
    function getTimeRemaining(uint256 tokenId) 
        external 
        view 
        returns (uint256) 
    {
        PassMetadata memory metadata = passMetadata[tokenId];
        
        if (!metadata.active || block.timestamp >= metadata.expiryTime) {
            return 0;
        }
        
        return metadata.expiryTime - block.timestamp;
    }
    
    /**
     * @notice Get all active passes for a creator
     */
    function getCreatorActivePasses(address creator) 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256[] memory allPasses = creatorPasses[creator];
        uint256 activeCount = 0;
        
        // Count active passes
        for (uint256 i = 0; i < allPasses.length; i++) {
            if (isPassValid(allPasses[i])) {
                activeCount++;
            }
        }
        
        // Create array of active passes
        uint256[] memory activePasses = new uint256[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allPasses.length; i++) {
            if (isPassValid(allPasses[i])) {
                activePasses[index] = allPasses[i];
                index++;
            }
        }
        
        return activePasses;
    }
    
    // ============ Soul-Bound Implementation ============
    
    /**
     * @notice Prevent token transfers (soul-bound)
     * @dev Overrides _update to make NFT non-transferable
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Allow minting (from == address(0))
        // Allow burning (to == address(0))
        // Block all other transfers
        if (from != address(0) && to != address(0)) {
            revert SoulBoundToken();
        }
        
        return super._update(to, tokenId, auth);
    }

    // ============ Required Overrides ============
    
    // function _burn(uint256 tokenId) 
    //     internal 
    //     override(ERC721, ERC721URIStorage) 
    // {
    //     super._burn(tokenId);
    //     delete passMetadata[tokenId];
    // }
    
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}