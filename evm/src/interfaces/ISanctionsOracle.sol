// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

/// @title ISanctionsOracle - Minimal sanctions screening interface.
/// @author Cobo Dev Team https://www.cobo.com/
/// @notice Single-method interface for on-chain sanctions screening: given an address, return
///         whether it should be blocked.
/// @dev Kept intentionally minimal so the backing implementation can be any of:
///      - A third-party on-chain sanctions oracle (view-only)
///      - An aggregator combining multiple compliance data sources
///      - An internal custom blacklist contract
///      Consumers depend only on this interface, never on a concrete implementation. The choice of
///      backing oracle is a runtime configuration decision (via `setSanctionsOracle`), not a
///      compile-time binding.
interface ISanctionsOracle {
    /// @notice Returns whether an address is on the sanctions list.
    /// @param addr The address to check.
    /// @return True if the address is sanctioned and should be blocked.
    function isSanctioned(address addr) external view returns (bool);
}
