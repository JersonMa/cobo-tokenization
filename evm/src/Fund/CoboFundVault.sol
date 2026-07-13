// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {LibFundErrors} from "./libraries/LibFundErrors.sol";
import {ISanctionsOracle} from "../interfaces/ISanctionsOracle.sol";

/// @notice Minimal interface for FundToken consumers.
interface ICoboFundToken {
    /// @notice Returns whether the system is paused.
    function paused() external view returns (bool);

    /// @notice Returns the configured sanctions screening oracle.
    /// @dev Vault reads this so sanctions configuration lives in a single place (FundToken).
    function sanctionsOracle() external view returns (ISanctionsOracle);
}

/// @title CoboFundVault - Asset custody vault for tokenized funds.
/// @author Cobo Safe Dev Team https://www.cobo.com/
/// @notice Holds all underlying asset token deposits and supports controlled withdrawals to whitelisted addresses.
/// @dev Reads FundToken's pause state for coordinated pause — does NOT inherit PausableUpgradeable.
///      Pre-approves FundToken for max asset tokens so FundToken can transferFrom for redemption payouts.
contract CoboFundVault is
    Initializable,
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    MulticallUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // ─── Constants ──────────────────────────────────────────────────────

    /// @notice Contract version for upgrade tracking.
    uint64 public constant VERSION = 1;

    /// @notice Role for addresses authorized to call withdraw.
    bytes32 public constant SETTLEMENT_OPERATOR_ROLE = keccak256("SETTLEMENT_OPERATOR_ROLE");

    /// @notice Role for addresses authorized to perform UUPS upgrades.
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ─── State Variables ────────────────────────────────────────────────

    /// @notice The underlying asset token.
    IERC20 public asset;

    /// @notice The FundToken contract (read paused state for coordinated pause).
    ICoboFundToken public fundToken;

    /// @notice Settlement target whitelist (project custody addresses).
    mapping(address => bool) public whitelist;

    // ─── Events ─────────────────────────────────────────────────────────

    event Withdrawn(address indexed to, uint256 amount, address indexed operator);
    event WhitelistUpdated(address indexed account, bool allowed);
    event FundTokenUpdated(address indexed fundToken);
    event RescueToken(address indexed token, address to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ─── Initializer ────────────────────────────────────────────────────

    /// @notice Initialize the vault with asset token, FundToken reference, and admin.
    /// @dev Automatically approves FundToken with max uint256 for asset token,
    ///      so FundToken can transferFrom to pay redemptions.
    /// @param asset_ Address of the underlying asset token.
    /// @param fundToken_ Address of the FundToken contract.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    function initialize(address asset_, address fundToken_, address admin) external initializer {
        if (asset_ == address(0)) revert LibFundErrors.ZeroAddress();
        if (fundToken_ == address(0)) revert LibFundErrors.ZeroAddress();
        if (admin == address(0)) revert LibFundErrors.ZeroAddress();

        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
        __Multicall_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        asset = IERC20(asset_);
        fundToken = ICoboFundToken(fundToken_);

        // Pre-approve FundToken to pull asset for redemption payments
        IERC20(asset_).forceApprove(fundToken_, type(uint256).max);
    }

    // ─── Asset Transfer (SETTLEMENT_OPERATOR_ROLE only) ─────────────────

    /// @notice Withdraw asset to a whitelisted address.
    /// @dev Sanctions screening uses the oracle configured on FundToken (single source of truth).
    ///      If FundToken's `sanctionsOracle` is unset (emergency disable), screening is bypassed.
    /// @param to Recipient address (must be in settlement whitelist).
    /// @param amount Amount of asset to transfer (asset token decimals).
    function withdraw(address to, uint256 amount) external onlyRole(SETTLEMENT_OPERATOR_ROLE) nonReentrant {
        if (to == address(0)) revert LibFundErrors.ZeroAddress();
        if (amount == 0) revert LibFundErrors.ZeroAmount();
        if (!whitelist[to]) revert LibFundErrors.NotInVaultWhitelist(to);
        if (fundToken.paused()) revert LibFundErrors.SystemPaused();

        ISanctionsOracle oracle_ = fundToken.sanctionsOracle();
        if (address(oracle_) != address(0) && oracle_.isSanctioned(to)) {
            revert LibFundErrors.AddressSanctioned(to);
        }

        asset.safeTransfer(to, amount);
        emit Withdrawn(to, amount, msg.sender);
    }

    // ─── Whitelist Management (DEFAULT_ADMIN_ROLE only) ─────────────────

    /// @notice Add or remove an address from the settlement target whitelist.
    function setWhitelist(address account, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert LibFundErrors.ZeroAddress();
        whitelist[account] = allowed;
        emit WhitelistUpdated(account, allowed);
    }

    // ─── Configuration (DEFAULT_ADMIN_ROLE only) ────────────────────────

    /// @notice Update the FundToken address. Re-approves the new address with max uint256.
    /// @dev Revokes old approval before granting new one.
    function setFundToken(address fundToken_) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (fundToken_ == address(0)) revert LibFundErrors.ZeroAddress();

        // Revoke old approval
        asset.forceApprove(address(fundToken), 0);

        fundToken = ICoboFundToken(fundToken_);

        // Approve new FundToken
        asset.forceApprove(fundToken_, type(uint256).max);

        emit FundTokenUpdated(fundToken_);
    }

    // ─── Admin Self-Protection ──────────────────────────────────────────

    /// @dev Prevents revoking the last DEFAULT_ADMIN_ROLE holder.
    function revokeRole(bytes32 role, address account) public override(AccessControlUpgradeable, IAccessControl) {
        if (
            role == DEFAULT_ADMIN_ROLE &&
            hasRole(DEFAULT_ADMIN_ROLE, account) &&
            getRoleMemberCount(DEFAULT_ADMIN_ROLE) == 1
        ) {
            revert LibFundErrors.LastAdminCannotBeRevoked();
        }
        super.revokeRole(role, account);
    }

    /// @dev Prevents renouncing the last DEFAULT_ADMIN_ROLE.
    function renounceRole(bytes32 role, address account) public override(AccessControlUpgradeable, IAccessControl) {
        if (role == DEFAULT_ADMIN_ROLE && getRoleMemberCount(DEFAULT_ADMIN_ROLE) == 1) {
            revert LibFundErrors.LastAdminCannotBeRevoked();
        }
        super.renounceRole(role, account);
    }

    // ─── Asset Rescue ───────────────────────────────────────────────────

    /// @notice Rescue accidentally sent ERC20 tokens (cannot rescue underlying asset tokens).
    function rescueERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert LibFundErrors.ZeroAddress();
        if (token == address(asset)) revert LibFundErrors.CannotRescueCoreAsset(token);
        IERC20(token).safeTransfer(to, amount);
        emit RescueToken(token, to, amount);
    }

    // ─── Version ────────────────────────────────────────────────────────

    /// @notice Returns the initialized version of the contract.
    function version() external view returns (uint64) {
        return uint64(_getInitializedVersion());
    }

    // ─── UUPS Upgrade Authorization ─────────────────────────────────────

    /* solhint-disable no-empty-blocks */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // ─── Storage Gap ────────────────────────────────────────────────────

    /// @dev Reserved storage for future upgrades.
    uint256[50] private __gap;
}
