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

}