// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {ISanctionsOracle} from "../../../src/Fund/interfaces/ISanctionsOracle.sol";

/// @dev Configurable sanctions oracle mock for unit tests.
///      Supports per-address toggling and a global "always reverts" mode for fail-close tests.
contract MockSanctionsOracle is ISanctionsOracle {
    mapping(address => bool) public sanctioned;
    bool public shouldRevert;

    function setSanctioned(address account, bool flag) external {
        sanctioned[account] = flag;
    }

    function setShouldRevert(bool flag) external {
        shouldRevert = flag;
    }

    function isSanctioned(address addr) external view override returns (bool) {
        require(!shouldRevert, "MockSanctionsOracle: revert");
        return sanctioned[addr];
    }
}
