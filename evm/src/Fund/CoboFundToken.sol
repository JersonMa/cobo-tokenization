// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {LibFundErrors} from "./libraries/LibFundErrors.sol";
import {ICoboFundOracle} from "./CoboFundOracle.sol";
import {ISanctionsOracle} from "./interfaces/ISanctionsOracle.sol";

/// @title CoboFundToken - ERC20 share token for asset-backed funds with NAV-based pricing.
/// @author Cobo Safe Dev Team https://www.cobo.com/
/// @notice Handles deposit, async redemption, whitelist, pause, and compliance operations.
/// @dev Decimal conversion uses precomputed scale factors for share and asset decimals.
///      NAV per share is in 1e18 precision, representing "1 share = nav/1e18 asset" in human terms.
contract CoboFundToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    MulticallUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // ─── Constants ──────────────────────────────────────────────────────

    /// @notice Contract version for upgrade tracking.
    uint64 public constant VERSION = 1;

    /// @notice Role for user whitelist management (add and remove).
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Role for approving/rejecting redemption requests.
    bytes32 public constant REDEMPTION_APPROVER_ROLE = keccak256("REDEMPTION_APPROVER_ROLE");

    /// @notice Role for emergency pause (one-way safety valve).
    bytes32 public constant EMERGENCY_GUARDIAN_ROLE = keccak256("EMERGENCY_GUARDIAN_ROLE");

    /// @notice Role for UUPS upgrades.
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 private constant _PRECISION = 1e18;

    // ─── Redemption Data Structures ─────────────────────────────────────

    enum RedemptionStatus {
        Pending,
        Rejected,
        Executed
    }

    struct RedemptionRequest {
        uint256 id;
        address user;
        uint256 assetAmount; // asset token amount to pay (asset token decimals)
        uint256 shareAmount; // share token amount burned (share token decimals)
        uint256 requestedAt;
        RedemptionStatus status;
    }

    // ─── State Variables ────────────────────────────────────────────────

    /// @notice The underlying asset token.
    IERC20 public asset;

    /// @notice The NAV oracle contract.
    ICoboFundOracle public oracle;

    /// @notice The asset custody vault.
    address public vault;

    /// @notice Minimum deposit amount in asset token decimals.
    uint256 public minDepositAmount;

    /// @notice Minimum redeem amount in share token decimals.
    uint256 public minRedeemShares;

    /// @notice Asset token decimals (cached from underlying asset token).
    uint8 public assetDecimals;

    /// @notice Share token decimals.
    uint8 private _decimals;

    /// @dev Scale factor: 10^assetDecimals.
    uint256 private _assetScale;

    /// @dev Scale factor: 10^shareDecimals.
    uint256 private _shareScale;

    /// @notice User whitelist — only whitelisted users can mint and redeem.
    mapping(address => bool) public whitelist;

    /// @notice Redemption requests.
    RedemptionRequest[] public redemptions;

    /// @notice Total asset amount owed to users across all Pending redemption requests.
    /// @dev Incremented on requestRedemption, decremented on approveRedemption/rejectRedemption.
    ///      Used by setVault() to verify the new vault has sufficient balance and allowance.
    uint256 public totalPendingAssets;

    /// @notice The sanctions screening oracle. Any contract implementing ISanctionsOracle.
    /// @dev When set to address(0), sanctions screening is bypassed — used as an emergency
    ///      fallback when the oracle is malfunctioning. Vault reads this via ICoboFundToken
    ///      to apply the same check on withdrawals. The choice of backing implementation is
    ///      a runtime configuration decision, not a compile-time binding.
    ISanctionsOracle public sanctionsOracle;

    // ─── Events ─────────────────────────────────────────────────────────

    // Redemption lifecycle
    event RedemptionRequested(
        uint256 indexed reqId,
        address indexed user,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 timestamp,
        address requestedBy
    );
    event RedemptionExecuted(
        uint256 indexed reqId,
        address indexed user,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 timestamp,
        address executedBy
    );
    event RedemptionRejected(
        uint256 indexed reqId,
        address indexed user,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 timestamp,
        address rejectedBy
    );
    event ForceRedeemed(address indexed user, uint256 shares, uint256 navAtTime);

    // Configuration
    event OracleUpdated(address indexed newOracle);
    event VaultUpdated(address indexed newVault);
    event WhitelistUpdated(address indexed account, bool allowed);
    event MinDepositAmountUpdated(uint256 minDepositAmount);
    event MinRedeemSharesUpdated(uint256 minRedeemShares);
    event RescueToken(address indexed token, address to, uint256 amount);

    // Sanctions screening
    event SanctionsOracleUpdated(address indexed newOracle);
    event RedemptionForfeited(
        uint256 indexed reqId,
        address indexed user,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 timestamp,
        address forfeitedBy
    );

    // ─── Constructor ────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ─── Initializer ────────────────────────────────────────────────────

    /// @notice Initialize the share management contract.
    /// @param name_ Token name (e.g., "Example Fund Token").
    /// @param symbol_ Token symbol (e.g., "EFT").
    /// @param decimals_ Token decimals (e.g., 18).
    /// @param asset_ Address of the underlying asset token.
    /// @param oracle_ Address of the NAV oracle.
    /// @param vault_ Address of the asset custody vault.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param minDepositAmount_ Minimum deposit in asset token decimals.
    /// @param minRedeemShares_ Minimum redeem in share token decimals.
    function initialize(
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        address asset_,
        address oracle_,
        address vault_,
        address admin,
        uint256 minDepositAmount_,
        uint256 minRedeemShares_
    ) external initializer {
        if (asset_ == address(0)) revert LibFundErrors.ZeroAddress();
        if (oracle_ == address(0)) revert LibFundErrors.ZeroAddress();
        if (vault_ == address(0)) revert LibFundErrors.ZeroAddress();
        if (admin == address(0)) revert LibFundErrors.ZeroAddress();

        __ERC20_init(name_, symbol_);
        __AccessControlEnumerable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __Multicall_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        _decimals = decimals_;
        asset = IERC20(asset_);
        oracle = ICoboFundOracle(oracle_);
        vault = vault_;
        minDepositAmount = minDepositAmount_;
        minRedeemShares = minRedeemShares_;

        // Compute scale factors for decimal conversion
        assetDecimals = IERC20Metadata(asset_).decimals();
        _assetScale = 10 ** uint256(assetDecimals);
        _shareScale = 10 ** uint256(decimals_);
    }

    // ─── ERC20 Overrides ────────────────────────────────────────────────

    /// @notice Returns the token decimals.
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @dev Unified transfer hook — enforces pause and sanctions screening.
    ///      All standard ERC20 operations (mint, burn, transfer) pass through here.
    ///      `forceRedeem` and `rejectRedemption` deliberately bypass this hook via
    ///      `_burnBypass` / `_mintBypass`; sanctions enforcement for those paths is
    ///      applied at the calling function entry instead.
    ///
    ///      Note on `from`/`to` zero-address handling: each side is checked independently,
    ///      not gated behind `from != 0 && to != 0`. This is intentional: unlike admin-push
    ///      token models (e.g. Backed Finance) where mint targets are vetted off-chain by the
    ///      minter, this contract is user-pull (users call `mint` themselves), so the
    ///      recipient on mint and the sender on burn (i.e. `requestRedemption`) MUST be
    ///      screened on-chain.
    function _update(address from, address to, uint256 amount) internal override whenNotPaused {
        if (from != address(0)) _requireNotSanctioned(from);
        if (to != address(0)) _requireNotSanctioned(to);
        super._update(from, to, amount);
    }

    // ─── Decimal Conversion Helpers ─────────────────────────────────────

    /// @dev Convert asset raw amount to share raw amount using NAV per share.
    ///      shares = assetAmount * shareScale * PRECISION / (nav * assetScale)
    ///      Pre-condition: assetAmount * _shareScale must not overflow uint256.
    ///      This holds in practice because assetAmount is bounded by the token's total supply
    ///      and _shareScale = 10^decimals (max 10^18 for 18-decimal tokens), and Solidity 0.8+
    ///      checked arithmetic will revert rather than silently overflow.
    function _assetToShares(uint256 assetAmount, uint256 nav) internal view returns (uint256) {
        return Math.mulDiv(assetAmount * _shareScale, _PRECISION, nav * _assetScale);
    }

    /// @dev Convert share raw amount to asset raw amount using NAV per share.
    ///      assetAmount = shareAmount * nav * assetScale / (shareScale * PRECISION)
    ///      Pre-condition: shareAmount * nav must not overflow uint256.
    ///      This holds in practice because shareAmount is bounded by totalSupply() and nav
    ///      grows linearly with APR, and Solidity 0.8+ checked arithmetic will revert rather
    ///      than silently overflow.
    function _sharesToAsset(uint256 shareAmount, uint256 nav) internal view returns (uint256) {
        return Math.mulDiv(shareAmount * nav, _assetScale, _shareScale * _PRECISION);
    }

    // ─── Sanctions Screening ────────────────────────────────────────────

    /// @dev Revert if `account` is on the sanctions list.
    ///      If `sanctionsOracle` is unset (address(0)), the check is bypassed — this is
    ///      the emergency-disable path entered via `setSanctionsOracle(address(0))`.
    function _requireNotSanctioned(address account) internal view {
        ISanctionsOracle o = sanctionsOracle;
        if (address(o) == address(0)) return;
        if (o.isSanctioned(account)) revert LibFundErrors.AddressSanctioned(account);
    }

    // ─── Bypass Functions ───────────────────────────────────────────────

    /// @dev Bypass mint — calls ERC20Upgradeable._update directly, bypassing our _update override
    ///      (and therefore its sanctions check). Used by `rejectRedemption` to mint shares back
    ///      to a user after a Pending redemption is rejected; sanctions enforcement for that path
    ///      is applied at `rejectRedemption`'s function entry.
    ///      Pause is still enforced via the `whenNotPaused` modifier here.
    function _mintBypass(address to, uint256 amount) internal whenNotPaused {
        super._update(address(0), to, amount);
    }

    /// @dev Bypass burn — calls ERC20Upgradeable._update directly, bypassing our _update override
    ///      (and therefore its sanctions check AND its pause check). Used by `forceRedeem`, which
    ///      must work against sanctioned users and must work while paused (compliance disposal tool).
    function _burnBypass(address from, uint256 amount) internal {
        super._update(from, address(0), amount);
    }

    // ─── Deposit ────────────────────────────────────────────────────────

    /// @notice Deposit asset tokens and receive shares.
    /// @param assetAmount Amount of asset to deposit (asset token decimals).
    /// @return shareAmount Amount of shares minted (share token decimals).
    function mint(uint256 assetAmount) external whenNotPaused nonReentrant returns (uint256 shareAmount) {
        if (!whitelist[msg.sender]) revert LibFundErrors.NotWhitelisted(msg.sender);
        if (assetAmount < minDepositAmount) revert LibFundErrors.BelowMinDeposit(assetAmount, minDepositAmount);

        uint256 nav = oracle.getLatestPrice();
        if (nav == 0) revert LibFundErrors.ZeroNetValue();

        shareAmount = _assetToShares(assetAmount, nav);
        if (shareAmount == 0) revert LibFundErrors.ZeroShares();

        // Transfer asset from user to Vault
        asset.safeTransferFrom(msg.sender, vault, assetAmount);

        // Mint shares to user (goes through _update with pause check)
        _mint(msg.sender, shareAmount);
    }

    // ─── Redemption Request ─────────────────────────────────────────────

    /// @notice Request redemption by burning shares.
    /// @param shareAmount Amount of shares to redeem (share token decimals).
    /// @return reqId Redemption request ID.
    function requestRedemption(uint256 shareAmount) external whenNotPaused returns (uint256 reqId) {
        if (!whitelist[msg.sender]) revert LibFundErrors.NotWhitelisted(msg.sender);
        if (shareAmount < minRedeemShares) revert LibFundErrors.BelowMinRedeem(shareAmount, minRedeemShares);

        uint256 nav = oracle.getLatestPrice();
        if (nav == 0) revert LibFundErrors.ZeroNetValue();

        // Convert shares to asset amount
        uint256 assetAmount = _sharesToAsset(shareAmount, nav);
        if (assetAmount == 0) revert LibFundErrors.ZeroAssetAmount();

        // Burn shares immediately (goes through _update)
        _burn(msg.sender, shareAmount);

        // Create request
        reqId = redemptions.length;
        redemptions.push(
            RedemptionRequest({
                id: reqId,
                user: msg.sender,
                assetAmount: assetAmount,
                shareAmount: shareAmount,
                requestedAt: block.timestamp,
                status: RedemptionStatus.Pending
            })
        );

        totalPendingAssets += assetAmount;
        emit RedemptionRequested(reqId, msg.sender, assetAmount, shareAmount, block.timestamp, msg.sender);
    }

    // ─── Redemption Approval ────────────────────────────────────────────

    /// @notice Approve a pending redemption. Pays asset from Vault to user.
    /// @dev user/assetAmount/shareAmount params are for Cobo Guard calldata signing verification.
    /// @param reqId Redemption request ID.
    /// @param user Expected user address (verified against stored request).
    /// @param assetAmount Expected asset token amount (verified against stored request).
    /// @param shareAmount Expected share token amount (verified against stored request).
    function approveRedemption(
        uint256 reqId,
        address user,
        uint256 assetAmount,
        uint256 shareAmount
    ) external onlyRole(REDEMPTION_APPROVER_ROLE) whenNotPaused nonReentrant {
        if (reqId >= redemptions.length) revert LibFundErrors.InvalidRedemptionRequest(reqId);
        RedemptionRequest storage req = redemptions[reqId];

        if (req.status != RedemptionStatus.Pending) revert LibFundErrors.RedemptionNotPending(reqId);
        if (req.user != user || req.assetAmount != assetAmount || req.shareAmount != shareAmount) {
            revert LibFundErrors.RedemptionParamMismatch(reqId);
        }
        if (!whitelist[user]) revert LibFundErrors.NotWhitelisted(user);
        _requireNotSanctioned(user);

        // Update status first (checks-effects-interactions)
        req.status = RedemptionStatus.Executed;
        totalPendingAssets -= assetAmount;

        // Pay asset from Vault to user (Vault has pre-approved this contract)
        asset.safeTransferFrom(vault, user, assetAmount);

        emit RedemptionExecuted(reqId, user, assetAmount, shareAmount, block.timestamp, msg.sender);
    }

    // ─── Redemption Rejection ───────────────────────────────────────────

    /// @notice Reject a pending redemption. Mints back shares to user.
    /// @dev Uses _mintBypass to return shares to user, bypassing the _update sanctions hook.
    ///      Sanctions are enforced here at the entry: a user listed between request and reject
    ///      cannot have shares restored. Stuck requests (both approve and reject blocked) are
    ///      cleared via `adminForfeitPending`.
    /// @param reqId Redemption request ID.
    /// @param user Expected user address (verified against stored request).
    /// @param assetAmount Expected asset token amount (verified against stored request).
    /// @param shareAmount Expected share token amount (verified against stored request).
    function rejectRedemption(
        uint256 reqId,
        address user,
        uint256 assetAmount,
        uint256 shareAmount
    ) external onlyRole(REDEMPTION_APPROVER_ROLE) whenNotPaused nonReentrant {
        if (reqId >= redemptions.length) revert LibFundErrors.InvalidRedemptionRequest(reqId);
        RedemptionRequest storage req = redemptions[reqId];

        if (req.status != RedemptionStatus.Pending) revert LibFundErrors.RedemptionNotPending(reqId);
        if (req.user != user || req.assetAmount != assetAmount || req.shareAmount != shareAmount) {
            revert LibFundErrors.RedemptionParamMismatch(reqId);
        }
        _requireNotSanctioned(user);

        req.status = RedemptionStatus.Rejected;
        totalPendingAssets -= assetAmount;

        // Mint back shares to user
        _mintBypass(user, shareAmount);

        emit RedemptionRejected(reqId, user, assetAmount, shareAmount, block.timestamp, msg.sender);
    }

    // ─── Compliance: Forfeiture Tools ───────────────────────────────────
    //
    // Two functions together cover every form a sanctioned user's assets can take inside the
    // system. Both are FORFEITURE operations (irreversible; user permanently loses claim) and
    // share the same legal-authority requirements (OFAC order, escheatment, system retirement).
    //
    //   - `forceRedeem`       → forfeits a user's SHARE BALANCE (tokens they still hold)
    //   - `adminForfeitPending` → forfeits a user's PENDING CLAIM (already-burned share, asset
    //                            sitting in Vault awaiting settlement)
    //
    // Default policy is to leave sanctioned users' assets frozen (do nothing) and wait for
    // delisting or OFAC instructions. Use these tools only with documented legal authority.

    /// @notice Forfeit a user's share balance — LAST-RESORT compliance tool.
    /// @dev FORFEITURE OPERATION. See policy note above. Pairs with `adminForfeitPending`
    ///      to cover the user's pending claims; together they exhaust every asset form a
    ///      sanctioned user can hold in this system.
    ///      Uses `_burnBypass` (skips sanctions check + pause); works even if system is paused.
    ///      If requested shares > balance, burns all available balance (auto-adjusts).
    ///      Pass type(uint256).max to clear user's entire balance.
    function forceRedeem(address user, uint256 shares) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (user == address(0)) revert LibFundErrors.ZeroAddress();
        if (shares == 0) revert LibFundErrors.ZeroAmount();

        uint256 balance = balanceOf(user);
        uint256 toBurn = shares > balance ? balance : shares;
        if (toBurn == 0) revert LibFundErrors.ZeroAmount();

        uint256 nav = oracle.getLatestPrice();
        _burnBypass(user, toBurn);
        emit ForceRedeemed(user, toBurn, nav);
    }

    /// @notice Forfeit a user's pending redemption claim — LAST-RESORT compliance tool.
    /// @dev On-chain mechanics are mild — this function only:
    ///        - flips `req.status` from Pending to Rejected
    ///        - decrements `totalPendingAssets` accounting
    ///        - emits `RedemptionForfeited`
    ///      It does NOT burn shares (already burned at request time), NOT pay asset out,
    ///      NOT transfer custody.
    ///
    ///      Economic effect IS forfeiture, however: the user's recorded claim is permanently
    ///      released, and the corresponding asset (still sitting in Vault) becomes orphaned
    ///      against the now-reduced `totalPendingAssets`. Operations must reconcile that
    ///      orphaned asset off-chain (typically reflected as an uplift to remaining holders'
    ///      NAV at the next oracle update).
    ///
    ///      Default policy for sanctions-induced stuck Pending is to LEAVE IT PENDING (blocked
    ///      transaction, OFAC-compliant). Awaiting OFAC instructions or user delisting is the
    ///      preferred path. Use this function only with documented legal authority:
    ///        1. OFAC forfeiture order against the user
    ///        2. User death / long-term disappearance + applicable escheatment law
    ///        3. System retirement / migration cleanup (governance-approved)
    ///      Off-chain MUST preserve the supporting document (OFAC reference, court order,
    ///      governance proposal) for audit.
    ///
    ///      For OFAC release-license cases (sanctioned user obtains permission to receive
    ///      funds), DO NOT use this — perform a one-shot contract upgrade with a time-bounded
    ///      force-approve helper instead, then upgrade again to remove it.
    ///
    ///      Pairs with `forceRedeem` to cover the user's share balance; together they exhaust
    ///      every asset form a sanctioned user can hold in this system.
    /// @param reqId Pending redemption request ID to forfeit.
    function adminForfeitPending(uint256 reqId) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (reqId >= redemptions.length) revert LibFundErrors.InvalidRedemptionRequest(reqId);
        RedemptionRequest storage req = redemptions[reqId];
        if (req.status != RedemptionStatus.Pending) revert LibFundErrors.RedemptionNotPending(reqId);

        req.status = RedemptionStatus.Rejected;
        totalPendingAssets -= req.assetAmount;

        emit RedemptionForfeited(reqId, req.user, req.assetAmount, req.shareAmount, block.timestamp, _msgSender());
    }

    // ─── Pause Control ──────────────────────────────────────────────────

    /// @notice Pause the system. Can be called by EMERGENCY_GUARDIAN_ROLE or DEFAULT_ADMIN_ROLE.
    function pause() external {
        if (!hasRole(EMERGENCY_GUARDIAN_ROLE, _msgSender()) && !hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {
            revert IAccessControl.AccessControlUnauthorizedAccount(_msgSender(), EMERGENCY_GUARDIAN_ROLE);
        }
        _pause();
    }

    /// @notice Unpause the system. Only DEFAULT_ADMIN_ROLE can unpause (asymmetric design).
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ─── Sanctions Oracle Control ───────────────────────────────────────

    /// @notice Set (or clear) the sanctions screening oracle.
    /// @dev Pass any contract implementing ISanctionsOracle (the concrete data source is a runtime
    ///      configuration decision — see the operations runbook).
    ///      Pass `address(0)` to disable screening (emergency fallback when the oracle is malfunctioning).
    ///      A non-zero candidate is validated by a lightweight conformance probe:
    ///      `isSanctioned(address(this))` must return `false`. The call reverts if the candidate's
    ///      staticcall reverts (non-conforming interface, no such function, etc.) or if it returns true
    ///      on this contract's address (clearly broken oracle, since this contract itself cannot be
    ///      sanctioned by any legitimate list). This is a smoke test for interface and basic sanity,
    ///      NOT a defense against a malicious oracle that returns true for arbitrary other addresses —
    ///      that risk is governed by trust in the oracle's deployer and the admin multisig.
    ///      Monitoring systems detect a disable by filtering `SanctionsOracleUpdated` for `newOracle == 0`.
    /// @param sanctionsOracle_ Address of the new sanctions oracle, or address(0) to disable screening.
    function setSanctionsOracle(address sanctionsOracle_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (sanctionsOracle_ != address(0)) {
            if (ISanctionsOracle(sanctionsOracle_).isSanctioned(address(this))) {
                revert LibFundErrors.InvalidSanctionsOracle(sanctionsOracle_);
            }
        }
        sanctionsOracle = ISanctionsOracle(sanctionsOracle_);
        emit SanctionsOracleUpdated(sanctionsOracle_);
    }

    // ─── Admin Configuration ────────────────────────────────────────────

    /// @notice Set the NAV oracle address.
    /// @dev Automatically pauses and unpauses around the switch to prevent any mint/redeem
    ///      activity during migration. If the contract is already paused, the pause state is
    ///      preserved after the call (i.e. it will not be unpaused).
    function setOracle(address oracle_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bool wasPaused = paused();
        if (!wasPaused) _pause();
        _setOracle(oracle_);
        if (!wasPaused) _unpause();
    }

    /// @dev Validates and applies the new oracle address.
    ///      The new oracle's current price must be >= the old oracle's to preserve NAV monotonicity.
    function _setOracle(address oracle_) internal {
        if (oracle_ == address(0)) revert LibFundErrors.ZeroAddress();
        uint256 oldPrice = oracle.getLatestPrice();
        uint256 newPrice = ICoboFundOracle(oracle_).getLatestPrice();
        if (newPrice < oldPrice) revert LibFundErrors.OraclePriceDecrease(oldPrice, newPrice);
        oracle = ICoboFundOracle(oracle_);
        emit OracleUpdated(oracle_);
    }

    /// @notice Set the asset custody vault address.
    /// @dev New vault must hold sufficient assets and have approved this contract for at least
    ///      totalPendingAssets, ensuring all outstanding redemptions remain executable after the switch.
    function setVault(address vault_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vault_ == address(0)) revert LibFundErrors.ZeroAddress();
        uint256 balance = asset.balanceOf(vault_);
        if (balance < totalPendingAssets) revert LibFundErrors.InsufficientVaultBalance(balance, totalPendingAssets);
        uint256 allowance = asset.allowance(vault_, address(this));
        if (allowance < totalPendingAssets)
            revert LibFundErrors.InsufficientVaultAllowance(allowance, totalPendingAssets);
        vault = vault_;
        emit VaultUpdated(vault_);
    }

    /// @notice Set minimum deposit amount in asset token decimals.
    function setMinDepositAmount(uint256 minDepositAmount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minDepositAmount = minDepositAmount_;
        emit MinDepositAmountUpdated(minDepositAmount_);
    }

    /// @notice Set minimum redeem shares in share token decimals.
    function setMinRedeemShares(uint256 minRedeemShares_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minRedeemShares = minRedeemShares_;
        emit MinRedeemSharesUpdated(minRedeemShares_);
    }

    // ─── Whitelist Management ───────────────────────────────────────────

    /// @notice Add a user to the whitelist (KYC approved).
    /// @dev Only MANAGER_ROLE can add users to the whitelist.
    ///      Whitelisted users can mint shares and request redemptions.
    ///      The whitelist check is enforced at business-logic entry points (mint, requestRedemption, approveRedemption).
    function addToWhitelist(address account) external onlyRole(MANAGER_ROLE) {
        if (account == address(0)) revert LibFundErrors.ZeroAddress();
        whitelist[account] = true;
        emit WhitelistUpdated(account, true);
    }

    /// @notice Remove a user from the whitelist (compliance enforcement).
    /// @dev Only MANAGER_ROLE can remove users from the whitelist.
    ///      Same role as addition allows immediate correction of mistakes.
    ///      Removed users cannot mint or redeem.
    ///      Their existing shares remain and can still be transferred.
    ///      Use forceRedeem() to clear a removed user's balance if required by compliance.
    function removeFromWhitelist(address account) external onlyRole(MANAGER_ROLE) {
        if (account == address(0)) revert LibFundErrors.ZeroAddress();
        whitelist[account] = false;
        emit WhitelistUpdated(account, false);
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

    /// @notice Rescue accidentally sent ERC20 tokens.
    /// @dev This contract should not hold any asset tokens or share tokens under normal operations.
    function rescueERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert LibFundErrors.ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit RescueToken(token, to, amount);
    }

    // ─── View Helpers ───────────────────────────────────────────────────

    /// @notice Returns the total number of redemption requests.
    function redemptionCount() external view returns (uint256) {
        return redemptions.length;
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
    uint256[48] private __gap;
}
