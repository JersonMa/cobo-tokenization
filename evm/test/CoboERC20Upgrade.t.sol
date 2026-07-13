// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {CoboERC20} from "../src/CoboERC20/CoboERC20.sol";
import {LibErrors} from "../src/CoboERC20/library/Errors/LibErrors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MockSanctionsOracle} from "./Fund/mocks/MockSanctionsOracle.sol";
import {CoboERC20LegacyMock} from "./mocks/CoboERC20LegacyMock.sol";

/// @dev V2 mock that appends a new state variable, used to prove the storage layout
///      (including the freshly-added `sanctionsOracle` slot) survives an upgrade.
contract CoboERC20V2Mock is CoboERC20 {
    uint256 public newVariable;

    function setNewVariable(uint256 v) external {
        newVariable = v;
    }
}

/// @dev Verifies that adding `sanctionsOracle` (and shrinking the storage gap) is upgrade-safe:
///      existing state and the new field both persist across a UUPS upgrade.
contract CoboERC20UpgradeTest is Test {
    CoboERC20 token;
    MockSanctionsOracle oracle;

    address admin = makeAddr("admin");
    address manager = makeAddr("manager");
    address minter = makeAddr("minter");
    address upgrader = makeAddr("upgrader");
    address alice = makeAddr("alice");
    address blocked = makeAddr("blocked");

    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function setUp() public {
        CoboERC20 logic = new CoboERC20();
        token = CoboERC20(address(new ERC1967Proxy(address(logic), "")));
        token.initialize("Cobo", "COBO", "https://cobo.com", 9, admin);

        vm.startPrank(admin);
        token.grantRole(MANAGER_ROLE, manager);
        token.grantRole(MINTER_ROLE, minter);
        token.grantRole(UPGRADER_ROLE, upgrader);
        vm.stopPrank();

        oracle = new MockSanctionsOracle();
        vm.prank(admin);
        token.setSanctionsOracle(address(oracle));
    }

    function test_sanctionsOraclePreservedAcrossUpgrade() public {
        // Establish V1 state.
        vm.prank(minter);
        token.mint(alice, 500e9);

        address[] memory list = new address[](1);
        list[0] = blocked;
        vm.prank(manager);
        token.blockListAdd(list);

        uint256 v1Balance = token.balanceOf(alice);
        uint8 v1Decimals = token.decimals();
        address v1Oracle = address(token.sanctionsOracle());

        // Upgrade to V2 (appends a new variable).
        CoboERC20V2Mock v2Impl = new CoboERC20V2Mock();
        vm.prank(upgrader);
        UUPSUpgradeable(address(token)).upgradeToAndCall(address(v2Impl), bytes(""));

        // All prior state preserved.
        assertEq(token.balanceOf(alice), v1Balance, "balance changed");
        assertEq(token.decimals(), v1Decimals, "decimals changed");
        assertEq(address(token.sanctionsOracle()), v1Oracle, "sanctionsOracle changed");
        assertTrue(token.isBlockListed(blocked), "blockList changed");

        // New variable defaults to 0 and setting it does not corrupt existing state.
        CoboERC20V2Mock v2 = CoboERC20V2Mock(address(token));
        assertEq(v2.newVariable(), 0, "newVariable not zero");
        v2.setNewVariable(42);
        assertEq(v2.newVariable(), 42, "newVariable not set");
        assertEq(address(token.sanctionsOracle()), v1Oracle, "sanctionsOracle corrupted by newVariable");
        assertEq(token.balanceOf(alice), v1Balance, "balance corrupted by newVariable");
    }

    /// @dev Real production migration: a proxy deployed on the pre-sanctions layout (no
    ///      `sanctionsOracle`) is upgraded to the current implementation. Existing state must
    ///      survive and the freshly-added field must read its default (screening off), after
    ///      which the oracle can be installed and enforcement begins.
    function test_migrationFromLegacyPreservesStateAndDefaultsOracleOff() public {
        // Deploy a legacy (pre-sanctions) proxy and establish state on the old layout.
        CoboERC20LegacyMock legacyImpl = new CoboERC20LegacyMock();
        address proxy = address(new ERC1967Proxy(address(legacyImpl), bytes("")));
        CoboERC20LegacyMock legacy = CoboERC20LegacyMock(proxy);
        legacy.initialize("Cobo", "COBO", "https://cobo.com", 9, admin);

        legacy.mint(alice, 500e9);
        address[] memory list = new address[](1);
        list[0] = blocked;
        legacy.blockListAdd(list);

        uint256 v1Balance = legacy.balanceOf(alice);
        uint8 v1Decimals = legacy.decimals();

        // Upgrade the same proxy to the current, sanctions-enabled implementation.
        CoboERC20 currentImpl = new CoboERC20();
        UUPSUpgradeable(proxy).upgradeToAndCall(address(currentImpl), bytes(""));
        CoboERC20 upgraded = CoboERC20(proxy);

        // Legacy state preserved across the layout change.
        assertEq(upgraded.balanceOf(alice), v1Balance, "balance changed");
        assertEq(upgraded.decimals(), v1Decimals, "decimals changed");
        assertTrue(upgraded.isBlockListed(blocked), "blockList changed");
        // The new field, sharing the `_decimals` slot's previously-zero bytes, reads address(0).
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
        upgraded.transfer(sanctionedRecipient, 1e9);
    }
}
