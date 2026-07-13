// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {ContractUriUpgradeable} from "../../src/CoboERC20/library/Utils/ContractUriUpgradeable.sol";
import {SalvageUpgradeable} from "../../src/CoboERC20/library/Utils/SalvageUpgradeable.sol";
import {PauseUpgradeable} from "../../src/CoboERC20/library/Utils/PauseUpgradeable.sol";
import {RoleAccessUpgradeable} from "../../src/CoboERC20/library/Utils/RoleAccessUpgradeable.sol";
import {AccessListUpgradeable} from "../../src/CoboERC20/library/Utils/AccessListUpgradeable.sol";

/// @dev Faithful pre-sanctions layout of CoboERC20: identical base-contract inheritance, then
///      `_decimals` + `__gap[50]`, with NO `sanctionsOracle`. Represents an on-chain deployment
///      that predates sanctions screening, so upgrading a proxy from this to the current CoboERC20
///      exercises the real production migration (new field lands in the previously-zero upper bytes
///      of the `_decimals` slot).
///      Authorization hooks are left open — this is a test-only fixture.
contract CoboERC20LegacyMock is
    Initializable,
    ERC20Upgradeable,
    MulticallUpgradeable,
    SalvageUpgradeable,
    ContractUriUpgradeable,
    PauseUpgradeable,
    RoleAccessUpgradeable,
    AccessListUpgradeable,
    UUPSUpgradeable
{
    uint8 internal _decimals;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string calldata name,
        string calldata symbol,
        string calldata uri,
        uint8 decimal,
        address admin
    ) external initializer {
        __UUPSUpgradeable_init();
        __ERC20_init(name, symbol);
        __Multicall_init();
        __Salvage_init();
        __ContractUri_init(uri);
        __Pause_init();
        __RoleAccess_init();
        __AccessList_init();

        _decimals = decimal;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /* solhint-disable no-empty-blocks */
    function _authorizeUpgrade(address) internal override {}

    function _authorizeSalvage() internal override {}

    function _authorizeContractUriUpdate() internal override {}

    function _authorizePause() internal override {}

    function _authorizeUnpause() internal override {}

    function _authorizeAccessList() internal override {}

    function _authorizeBlockList() internal override {}

    uint256[50] private __gap;
}
