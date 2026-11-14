// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IHyperionPositionToken} from "../interfaces/IHyperionPositionToken.sol";

/**
 * @title HyperionPositionToken
 * @notice ERC-721 tokenized wrapper for isolated perpetual futures positions.
 * @dev Enables secondary DeFi composability, position transfers, and vault tokenization.
 */
contract HyperionPositionToken is ERC721, IHyperionPositionToken {
    // =========================================================================
    // IMMUTABLES
    // =========================================================================

    address public immutable clearingHouse;
    address public immutable owner;

    // =========================================================================
    // STATE
    // =========================================================================

    struct TokenMetadata {
        uint256 marketId;
        Side side;
        uint256 mintTimestamp;
    }

    // Token ID => Metadata
    mapping(uint256 => TokenMetadata) public tokenMetadata;

    uint256 private _nextTokenId = 1;

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyClearingHouse() {
        if (msg.sender != clearingHouse) revert UnauthorizedCaller();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(address _clearingHouse, address _owner) ERC721("Hyperion Position NFT", "HYP-POS") {
        if (_clearingHouse == address(0) || _owner == address(0)) revert ZeroAddress();
        clearingHouse = _clearingHouse;
        owner = _owner;
    }

    // =========================================================================
    // TOKEN LIFECYCLE
    // =========================================================================

    /// @inheritdoc IHyperionPositionToken
    function mintPosition(address recipient, uint256 marketId, Side side)
        external
        override
        onlyClearingHouse
        returns (uint256 tokenId)
    {
        if (recipient == address(0)) revert ZeroAddress();

        tokenId = _nextTokenId++;
        _safeMint(recipient, tokenId);

        tokenMetadata[tokenId] = TokenMetadata({marketId: marketId, side: side, mintTimestamp: block.timestamp});

        emit PositionNFTMinted(tokenId, recipient, marketId, side);
    }

    /// @inheritdoc IHyperionPositionToken
    function burnPosition(uint256 tokenId) external override onlyClearingHouse {
        _burn(tokenId);
        delete tokenMetadata[tokenId];
        emit PositionNFTBurned(tokenId);
    }

    /// @inheritdoc IHyperionPositionToken
    function getPositionMetadata(uint256 tokenId) external view override returns (uint256 marketId, Side side) {
        TokenMetadata memory meta = tokenMetadata[tokenId];
        return (meta.marketId, meta.side);
    }
}
