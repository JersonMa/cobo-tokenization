// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import {ERC20Upgradeable, IERC20, IERC20Metadata} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ContractUriUpgradeable} from "../../src/CoboERC20/library/Utils/ContractUriUpgradeable.sol";
import {SalvageUpgradeable} from "../../src/CoboERC20/library/Utils/SalvageUpgradeable.sol";
import {PauseUpgradeable} from "../../src/CoboERC20/library/Utils/PauseUpgradeable.sol";
import {RoleAccessUpgradeable} from "../../src/CoboERC20/library/Utils/RoleAccessUpgradeable.sol";
import {AccessListUpgradeable} from "../../src/CoboERC20/library/Utils/AccessListUpgradeable.sol";

/// @dev Faithful pre-sanctions layout of CoboERC20Wrapper: identical base-contract inheritance, then
///      `_decimals` + `_underlying` + `__gap[49]`, with NO `sanctionsOracle`. Represents an on-chain
///      deployment that predates sanctions screening, so upgrading a proxy from this to the current
///      CoboERC20Wrapper exercises the real production migration. Unlike CoboERC20, `sanctionsOracle`
///      here lands in a brand-new slot (because `_decimals` + `_underlying` already fill the packable
///      space of their slot) and the gap shrinks from 49 to 48 — the higher-risk "new slot + smaller
///      gap" path.
///      Authorization hooks are left open — this is a test-only fixture.
contract CoboERC20WrapperLegacyMock is
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
    using SafeERC20 for IERC20;

    uint8 internal _decimals;
    IERC20 private _underlying;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address underlyingToken,
        string calldata name,
        string calldata symbol,
        string calldata uri,
        address admin
    ) external initializer {
        _underlying = IERC20(underlyingToken);
        _decimals = IERC20Metadata(underlyingToken).decimals();

        __UUPSUpgradeable_init();
        __ERC20_init(name, symbol);
        __Multicall_init();
        __Salvage_init();
        __ContractUri_init(uri);
        __Pause_init();
        __RoleAccess_init();
        __AccessList_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function underlying() public view returns (IERC20) {
        return _underlying;
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

    uint256[49] private __gap;
}
