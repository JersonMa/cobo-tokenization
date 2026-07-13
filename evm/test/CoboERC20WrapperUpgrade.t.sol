// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {CoboERC20Wrapper} from "../src/CoboERC20/CoboERC20Wrapper.sol";
import {LibErrors} from "../src/CoboERC20/library/Errors/LibErrors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MockSanctionsOracle} from "./Fund/mocks/MockSanctionsOracle.sol";
import {MockERC20} from "./Fund/mocks/MockERC20.sol";
import {CoboERC20WrapperLegacyMock} from "./mocks/CoboERC20WrapperLegacyMock.sol";

/// @dev V2 mock that appends a new state variable, used to prove the storage layout
///      (including the freshly-added `sanctionsOracle` slot) survives an upgrade.
contract CoboERC20WrapperV2Mock is CoboERC20Wrapper {
    uint256 public newVariable;

    function setNewVariable(uint256 v) external {
        newVariable = v;
    }
}

/// @dev Verifies that adding `sanctionsOracle` (which consumes a NEW storage slot in the Wrapper and
///      shrinks the gap from 49 to 48) is upgrade-safe: existing state and the new field both persist
///      across a UUPS upgrade, and a proxy deployed on the pre-sanctions layout migrates cleanly.
contract CoboERC20WrapperUpgradeTest is Test {
    CoboERC20Wrapper wrapper;
    MockSanctionsOracle oracle;
    MockERC20 underlying;

    address admin = makeAddr("admin");
    address manager = makeAddr("manager");
    address minter = makeAddr("minter");
    address upgrader = makeAddr("upgrader");
    address alice = makeAddr("alice");
    address blocked = makeAddr("blocked");

    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 constant WRAPPER_ROLE = keccak256("WRAPPER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 constant AMOUNT = 1000e18;

    function setUp() public {
        underlying = new MockERC20("Under", "UND", 18);

        CoboERC20Wrapper logic = new CoboERC20Wrapper();
        wrapper = CoboERC20Wrapper(address(new ERC1967Proxy(address(logic), "")));
        wrapper.initialize(address(underlying), "Wrapped", "wUND", "https://cobo.com", admin);

        vm.startPrank(admin);
        wrapper.grantRole(MANAGER_ROLE, manager);
        wrapper.grantRole(MINTER_ROLE, minter);
        wrapper.grantRole(WRAPPER_ROLE, alice);
        wrapper.grantRole(UPGRADER_ROLE, upgrader);
        vm.stopPrank();

        oracle = new MockSanctionsOracle();
        vm.prank(admin);
        wrapper.setSanctionsOracle(address(oracle));

        underlying.mint(alice, AMOUNT);
        vm.prank(alice);
        underlying.approve(address(wrapper), type(uint256).max);
    }

    function test_sanctionsOraclePreservedAcrossUpgrade() public {
        // Establish V1 state.
        vm.prank(alice);
        wrapper.deposit(AMOUNT);

        address[] memory list = new address[](1);
        list[0] = blocked;
        vm.prank(manager);
        wrapper.blockListAdd(list);

        uint256 v1Balance = wrapper.balanceOf(alice);
        uint8 v1Decimals = wrapper.decimals();
        address v1Underlying = address(wrapper.underlying());
        address v1Oracle = address(wrapper.sanctionsOracle());

        // Upgrade to V2 (appends a new variable).
        CoboERC20WrapperV2Mock v2Impl = new CoboERC20WrapperV2Mock();
        vm.prank(upgrader);
        UUPSUpgradeable(address(wrapper)).upgradeToAndCall(address(v2Impl), bytes(""));

        // All prior state preserved.
        assertEq(wrapper.balanceOf(alice), v1Balance, "balance changed");
        assertEq(wrapper.decimals(), v1Decimals, "decimals changed");
        assertEq(address(wrapper.underlying()), v1Underlying, "underlying changed");
        assertEq(address(wrapper.sanctionsOracle()), v1Oracle, "sanctionsOracle changed");
        assertTrue(wrapper.isBlockListed(blocked), "blockList changed");

        // New variable defaults to 0 and setting it does not corrupt existing state.
        CoboERC20WrapperV2Mock v2 = CoboERC20WrapperV2Mock(address(wrapper));
        assertEq(v2.newVariable(), 0, "newVariable not zero");
        v2.setNewVariable(42);
        assertEq(v2.newVariable(), 42, "newVariable not set");
        assertEq(address(wrapper.sanctionsOracle()), v1Oracle, "sanctionsOracle corrupted by newVariable");
        assertEq(address(wrapper.underlying()), v1Underlying, "underlying corrupted by newVariable");
        assertEq(wrapper.balanceOf(alice), v1Balance, "balance corrupted by newVariable");
    }

    /// @dev Real production migration: a proxy deployed on the pre-sanctions layout (`_decimals` +
    ///      `_underlying` + `__gap[49]`, no `sanctionsOracle`) is upgraded to the current
    ///      implementation, where `sanctionsOracle` takes a brand-new slot and the gap shrinks to 48.
    ///      Existing state must survive and the freshly-added field must read its default (screening
    ///      off), after which the oracle can be installed and enforcement begins.
    function test_migrationFromLegacyPreservesStateAndDefaultsOracleOff() public {
        // Deploy a legacy (pre-sanctions) proxy and establish state on the old layout.
        CoboERC20WrapperLegacyMock legacyImpl = new CoboERC20WrapperLegacyMock();
        address proxy = address(new ERC1967Proxy(address(legacyImpl), bytes("")));
        CoboERC20WrapperLegacyMock legacy = CoboERC20WrapperLegacyMock(proxy);
        legacy.initialize(address(underlying), "Wrapped", "wUND", "https://cobo.com", admin);

        legacy.mint(alice, AMOUNT);
        address[] memory list = new address[](1);
        list[0] = blocked;
        legacy.blockListAdd(list);

        uint256 v1Balance = legacy.balanceOf(alice);
        uint8 v1Decimals = legacy.decimals();
        address v1Underlying = address(legacy.underlying());

        // Upgrade the same proxy to the current, sanctions-enabled implementation.
        CoboERC20Wrapper currentImpl = new CoboERC20Wrapper();
        UUPSUpgradeable(proxy).upgradeToAndCall(address(currentImpl), bytes(""));
        CoboERC20Wrapper upgraded = CoboERC20Wrapper(proxy);

        // Legacy state preserved across the layout change.
        assertEq(upgraded.balanceOf(alice), v1Balance, "balance changed");
        assertEq(upgraded.decimals(), v1Decimals, "decimals changed");
        assertEq(address(upgraded.underlying()), v1Underlying, "underlying changed");
        assertTrue(upgraded.isBlockListed(blocked), "blockList changed");
        // The new field, landing in the previously-zero gap slot, reads address(0).
        assertEq(address(upgraded.sanctionsOracle()), address(0), "sanctionsOracle not default-zero");

        // Screening can be activated post-migration and enforces immediately.
        // Use a fresh address (not on the block list) so the revert is the sanctions check,
        // not the block-list check that runs earlier in transfer().
        address sanctionedRecipient = makeAddr("sanctionedRecipient");
        MockSanctionsOracle o = new MockSanctionsOracle();
        o.setSanctioned(sanctionedRecipient, true);
        vm.prank(admin);
        upgraded.setSanctionsOracle(address(o));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, sanctionedRecipient));
        upgraded.transfer(sanctionedRecipient, 1e18);
    }
}
