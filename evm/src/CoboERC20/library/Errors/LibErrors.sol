// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

/**
 * @title Errors Library
 * @author Cobo Dev Team https://www.cobo.com/
 * @notice The Errors Library provides error messages for the CoboERC20 contract.
 */
library LibErrors {
    /// Errors

    /**
     * @dev Indicates a failure that an address is not valid.
     */
    error InvalidAddress();

    /**
     * @dev Indicates a failure that an address is blocked.
     */
    error BlockedAddress(address account);

    /**
     * @dev Indicates a failure that an address is not in the access list.
     */
    error NotAccessListAddress(address account);

    /**
     * @dev Indicates a failure that a value is zero.
     */
    error ZeroAmount();

    /**
     * @dev Indicates a failure while salvaging native token.
     */
    error SalvageNativeFailed();

    /**
     * @dev Indicates a failure because "DEFAULT_ADMIN_ROLE" was tried to be revoked.
     */
    error DefaultAdminError();

    /**
     * @dev Indicates a failure that an address is on the sanctions list.
     */
    error AddressSanctioned(address account);
}
