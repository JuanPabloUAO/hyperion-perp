// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IHyperionTypes} from "./IHyperionTypes.sol";

/**
 * @title IHyperionPositionToken
 * @notice ERC-721 tokenized wrapper representing isolated perpetual positions.
 * @dev Enables secondary composability (collateralization, transfers, vault packaging) for perpetuals.
 */
interface IHyperionPositionToken is IERC721, IHyperionTypes {
    event PositionNFTMinted(uint256 indexed tokenId, address indexed recipient, uint256 marketId, Side side);
    event PositionNFTBurned(uint256 indexed tokenId);

    /**
     * @notice Mints an ERC-721 token binding to an isolated perpetual position.
     * @dev Only callable by the authorized ClearingHouse.
     * @param recipient Owner of the created position NFT
     * @param marketId Market identifier
     * @param side Long or Short
     * @return tokenId Minted NFT identifier
     */
    function mintPosition(address recipient, uint256 marketId, Side side) external returns (uint256 tokenId);

    /**
     * @notice Burns an existing position token upon full position exit.
     * @param tokenId Identifier of the token to burn
     */
    function burnPosition(uint256 tokenId) external;

    /**
     * @notice Returns associated market identifier and side for a position token.
     */
    function getPositionMetadata(uint256 tokenId) external view returns (uint256 marketId, Side side);
}
