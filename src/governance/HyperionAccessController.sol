// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "../interfaces/IHyperionTypes.sol";

/**
 * @title HyperionAccessController
 * @notice Role-based capability governance with 2-step admin transfer and emergency pause guardian.
 * @dev Manages operational permissions across ClearingHouse, Margin, VAMM, and Risk engines.
 */
contract HyperionAccessController is IHyperionTypes {
    // =========================================================================
    // ROLES (Packed bitmasks)
    // =========================================================================

    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
    bytes32 public constant ROLE_RISK_OPERATOR = keccak256("ROLE_RISK_OPERATOR");
    bytes32 public constant ROLE_KEEPER = keccak256("ROLE_KEEPER");
    bytes32 public constant ROLE_PAUSE_GUARDIAN = keccak256("ROLE_PAUSE_GUARDIAN");

    // =========================================================================
    // STATE
    // =========================================================================

    address public owner;
    address public pendingOwner;

    // Role => Account => HasRole
    mapping(bytes32 => mapping(address => bool)) public hasRole;

    // Global emergency pause
    bool public isPaused;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event OwnershipTransferStarted(address indexed currentOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event EmergencyPausedTriggered(address indexed guardian);
    event EmergencyUnpaused(address indexed admin);

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedCaller();
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!hasRole[role][msg.sender] && msg.sender != owner) revert UnauthorizedCaller();
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert EmergencyPaused();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(address _initialOwner) {
        if (_initialOwner == address(0)) revert ZeroAddress();
        owner = _initialOwner;
        hasRole[ROLE_ADMIN][_initialOwner] = true;
        hasRole[ROLE_RISK_OPERATOR][_initialOwner] = true;
        hasRole[ROLE_PAUSE_GUARDIAN][_initialOwner] = true;
    }

    // =========================================================================
    // TWO-STEP OWNERSHIP
    // =========================================================================

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert UnauthorizedCaller();
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
        hasRole[ROLE_ADMIN][owner] = true;
    }

    // =========================================================================
    // ROLE MANAGEMENT
    // =========================================================================

    function grantRole(bytes32 role, address account) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        hasRole[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    function revokeRole(bytes32 role, address account) external onlyOwner {
        hasRole[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    // =========================================================================
    // EMERGENCY PAUSE
    // =========================================================================

    function pause() external onlyRole(ROLE_PAUSE_GUARDIAN) {
        isPaused = true;
        emit EmergencyPausedTriggered(msg.sender);
    }

    function unpause() external onlyOwner {
        isPaused = false;
        emit EmergencyUnpaused(msg.sender);
    }
}
