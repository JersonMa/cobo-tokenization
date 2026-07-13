// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

/// @title LibFundErrors - Centralized custom errors for Fund contracts.
/// @author Cobo Safe Dev Team https://www.cobo.com/
library LibFundErrors {
    // ──────────────────── Common ────────────────────
    error ZeroAddress();
    error ZeroAmount();

    // ──────────────────── FundOracle ─────────────────
    error ZeroNetValue();
    error APRExceedsMax(uint256 apr, uint256 maxAPR);
    error APRDeltaExceedsMax(uint256 delta, uint256 maxAprDelta);
    error UpdateTooFrequent(uint256 elapsed, uint256 minInterval);

    // ──────────────────── FundToken ───────────────────
    error NotWhitelisted(address account);
    error BelowMinDeposit(uint256 amount, uint256 minDeposit);
    error BelowMinRedeem(uint256 shares, uint256 minRedeem);
    error ZeroShares();
    error ZeroAssetAmount();
    error OraclePriceDecrease(uint256 oldPrice, uint256 newPrice);
    error InsufficientVaultBalance(uint256 available, uint256 required);
    error InsufficientVaultAllowance(uint256 available, uint256 required);
    error InvalidRedemptionRequest(uint256 reqId);
    error RedemptionNotPending(uint256 reqId);
    error RedemptionParamMismatch(uint256 reqId);
    error CannotRescueCoreAsset(address token);

    // ──────────────────── FundVault ──────────────────
    error SystemPaused();
    error NotInVaultWhitelist(address to);

    // ──────────────────── Sanctions ──────────────────
    error AddressSanctioned(address account);

    // ──────────────────── AccessControl ─────────────
    error LastAdminCannotBeRevoked();
}
