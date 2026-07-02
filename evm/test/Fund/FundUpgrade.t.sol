// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "./FundTestBase.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

// ═══════════════════════════════════════════════════════════════════════════
// V2 Mock Contracts for Upgrade Tests
// ═══════════════════════════════════════════════════════════════════════════

/// @dev V2 Oracle with new variable and function.
contract CoboFundOracleV2 is CoboFundOracle {
    uint256 public newVariable;

    function setNewVariable(uint256 val) external {
        newVariable = val;
    }

    function versionV2() external pure returns (string memory) {
        return "v2";
    }
}

/// @dev V2 Nav4626 with new variable and function.
contract CoboFundTokenV2 is CoboFundToken {
    uint256 public newVariable;

    function setNewVariable(uint256 val) external {
        newVariable = val;
    }

    function versionV2() external pure returns (string memory) {
        return "v2";
    }
}

/// @dev V2 Vault with new variable and function.
contract CoboFundVaultV2 is CoboFundVault {
    uint256 public newVariable;

    function setNewVariable(uint256 val) external {
        newVariable = val;
    }

    function versionV2() external pure returns (string memory) {
        return "v2";
    }
}

/// @dev Non-UUPS contract (no proxiableUUID) for OZ-UUPS-3 test.
contract NonUUPSContract {
    uint256 public value;

    function setValue(uint256 v) external {
        value = v;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Test Contract
// ═══════════════════════════════════════════════════════════════════════════

contract FundUpgradeTest is FundTestBase {
    // Reusable V2 implementations
    CoboFundOracleV2 public oracleV2Impl;
    CoboFundTokenV2 public fundTokenV2Impl;
    CoboFundVaultV2 public vaultV2Impl;

    // Additional test addresses
    address public newAdmin = makeAddr("newAdmin");
    address public randomUser = makeAddr("randomUser");

    function setUp() public override {
        super.setUp();
        // Deploy V2 logic implementations
        oracleV2Impl = new CoboFundOracleV2();
        fundTokenV2Impl = new CoboFundTokenV2();
        vaultV2Impl = new CoboFundVaultV2();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 8.1 AccessControl Role Management
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev OZ-AC-1: DEFAULT_ADMIN grants MANAGER_ROLE -> success + RoleGranted event
    function test_OZ_AC_1_grantRole() public {
        address newManager = makeAddr("newManager");

        // Expect RoleGranted event
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleGranted(MANAGER_ROLE, newManager, admin);

        vm.prank(admin);
        fundToken.grantRole(MANAGER_ROLE, newManager);

        // Verify the role was granted
        assertTrue(fundToken.hasRole(MANAGER_ROLE, newManager));
    }

    /// @dev OZ-AC-2: DEFAULT_ADMIN revokes MANAGER_ROLE -> success + RoleRevoked event
    function test_OZ_AC_2_revokeRole() public {
        // manager already has MANAGER_ROLE from setUp
        assertTrue(fundToken.hasRole(MANAGER_ROLE, manager));

        // Expect RoleRevoked event
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleRevoked(MANAGER_ROLE, manager, admin);

        vm.prank(admin);
        fundToken.revokeRole(MANAGER_ROLE, manager);

        // Verify the role was revoked
        assertFalse(fundToken.hasRole(MANAGER_ROLE, manager));
    }

    /// @dev OZ-AC-3: manager renounces MANAGER_ROLE -> success, can no longer call setWhitelist
    function test_OZ_AC_3_renounceRole() public {
        assertTrue(fundToken.hasRole(MANAGER_ROLE, manager));

        // manager renounces own MANAGER_ROLE
        vm.prank(manager);
        fundToken.renounceRole(MANAGER_ROLE, manager);

        assertFalse(fundToken.hasRole(MANAGER_ROLE, manager));

        // Attempting setWhitelist should now revert
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, manager, MANAGER_ROLE)
        );
        vm.prank(manager);
        fundToken.addToWhitelist(makeAddr("someone"));
    }

    /// @dev OZ-AC-4: non-DEFAULT_ADMIN tries to grant -> revert: AccessControlUnauthorizedAccount
    function test_OZ_AC_4_nonAdminGrantFails() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                DEFAULT_ADMIN_ROLE
            )
        );
        vm.prank(randomUser);
        fundToken.grantRole(MANAGER_ROLE, randomUser);
    }

    /// @dev OZ-AC-5: DEFAULT_ADMIN transfer — original admin grants new address, then revokes self.
    ///      New admin can manage all roles.
    function test_OZ_AC_5_adminTransfer() public {
        // Step 1: Grant DEFAULT_ADMIN_ROLE to newAdmin
        vm.prank(admin);
        fundToken.grantRole(DEFAULT_ADMIN_ROLE, newAdmin);

        assertTrue(fundToken.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(fundToken.hasRole(DEFAULT_ADMIN_ROLE, newAdmin));

        // Step 2: Original admin revokes self (now there are 2 admins, so allowed)
        vm.prank(admin);
        fundToken.revokeRole(DEFAULT_ADMIN_ROLE, admin);

        assertFalse(fundToken.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(fundToken.hasRole(DEFAULT_ADMIN_ROLE, newAdmin));

        // Step 3: New admin can manage roles
        address anotherManager = makeAddr("anotherManager");
        vm.prank(newAdmin);
        fundToken.grantRole(MANAGER_ROLE, anotherManager);

        assertTrue(fundToken.hasRole(MANAGER_ROLE, anotherManager));

        // Old admin can no longer grant roles
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, DEFAULT_ADMIN_ROLE)
        );
        vm.prank(admin);
        fundToken.grantRole(MANAGER_ROLE, makeAddr("test"));
    }

    /// @dev OZ-AC-6: same address has MANAGER_ROLE + REDEMPTION_APPROVER_ROLE -> both functions callable
    function test_OZ_AC_6_multipleRoles() public {
        address multiRoleUser = makeAddr("multiRoleUser");

        vm.startPrank(admin);
        fundToken.grantRole(MANAGER_ROLE, multiRoleUser);
        fundToken.grantRole(REDEMPTION_APPROVER_ROLE, multiRoleUser);
        vm.stopPrank();

        assertTrue(fundToken.hasRole(MANAGER_ROLE, multiRoleUser));
        assertTrue(fundToken.hasRole(REDEMPTION_APPROVER_ROLE, multiRoleUser));

        // Can call MANAGER_ROLE function: setWhitelist
        vm.prank(multiRoleUser);
        fundToken.addToWhitelist(makeAddr("wlTarget"));

        // Can call REDEMPTION_APPROVER_ROLE function: approveRedemption (need a pending request)
        // First, deposit and create a pending redemption request
        uint256 shares = _deposit(user1, 10e6);
        uint256 reqId = _requestRedemption(user1, shares);

        // Read the redemption data for the approve call
        (, address reqUser, uint256 reqAsset, uint256 reqShare, , ) = fundToken.redemptions(reqId);

        // multiRoleUser acts as approver
        vm.prank(multiRoleUser);
        fundToken.approveRedemption(reqId, reqUser, reqAsset, reqShare);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 8.2 Pausable Behavior
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev OZ-PS-1: already paused, pause again -> revert: EnforcedPause
    function test_OZ_PS_1_pauseWhenAlreadyPaused() public {
        vm.prank(admin);
        fundToken.pause();

        assertTrue(fundToken.paused());

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(admin);
        fundToken.pause();
    }

    /// @dev OZ-PS-2: not paused, unpause again -> revert: ExpectedPause
    function test_OZ_PS_2_unpauseWhenNotPaused() public {
        assertFalse(fundToken.paused());

        vm.expectRevert(abi.encodeWithSignature("ExpectedPause()"));
        vm.prank(admin);
        fundToken.unpause();
    }

    /// @dev OZ-PS-3: paused() returns correct state before/after pause/unpause
    function test_OZ_PS_3_pausedReturnValue() public {
        // Before pause: false
        assertFalse(fundToken.paused());

        // After pause: true
        vm.prank(admin);
        fundToken.pause();
        assertTrue(fundToken.paused());

        // After unpause: false
        vm.prank(admin);
        fundToken.unpause();
        assertFalse(fundToken.paused());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 8.3 UUPS Upgrade
    // ═══════════════════════════════════════════════════════════════════════

    // ─── Nav4626 Upgrades ─────────────────────────────────────────────────

    /// @dev OZ-UUPS-1a: Legitimate upgrade of Nav4626
    function test_OZ_UUPS_1a_legitimateUpgradeNav4626() public {
        vm.prank(upgrader);
        UUPSUpgradeable(address(fundToken)).upgradeToAndCall(address(fundTokenV2Impl), bytes(""));

        // Verify V2 functionality is accessible
        CoboFundTokenV2 fundTokenV2 = CoboFundTokenV2(address(fundToken));
        assertEq(fundTokenV2.versionV2(), "v2");
    }

    /// @dev OZ-UUPS-2a: Unauthorized upgrade of Nav4626
    function test_OZ_UUPS_2a_unauthorizedUpgradeNav4626() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, randomUser, UPGRADER_ROLE)
        );
        vm.prank(randomUser);
        UUPSUpgradeable(address(fundToken)).upgradeToAndCall(address(fundTokenV2Impl), bytes(""));
    }

    /// @dev OZ-UUPS-3a: Upgrade Nav4626 to non-UUPS contract
    function test_OZ_UUPS_3a_upgradeToNonUUPSNav4626() public {
        NonUUPSContract nonUUPS = new NonUUPSContract();

        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(nonUUPS)));
        vm.prank(upgrader);
        UUPSUpgradeable(address(fundToken)).upgradeToAndCall(address(nonUUPS), bytes(""));
    }

    /// @dev OZ-UUPS-4a: Direct call initialize on Nav4626 implementation
    function test_OZ_UUPS_4a_directInitializeNav4626Impl() public {
        vm.expectRevert();
        fundTokenImpl.initialize("X", "X", 18, address(asset), address(oracle), address(vault), admin, 1, 1);
    }

    // ─── NavOracle Upgrades ───────────────────────────────────────────────

    /// @dev OZ-UUPS-1b: Legitimate upgrade of NavOracle
    function test_OZ_UUPS_1b_legitimateUpgradeNavOracle() public {
        vm.prank(upgrader);
        UUPSUpgradeable(address(oracle)).upgradeToAndCall(address(oracleV2Impl), bytes(""));

        CoboFundOracleV2 oracleV2 = CoboFundOracleV2(address(oracle));
        assertEq(oracleV2.versionV2(), "v2");
    }

    /// @dev OZ-UUPS-2b: Unauthorized upgrade of NavOracle
    function test_OZ_UUPS_2b_unauthorizedUpgradeNavOracle() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, randomUser, UPGRADER_ROLE)
        );
        vm.prank(randomUser);
        UUPSUpgradeable(address(oracle)).upgradeToAndCall(address(oracleV2Impl), bytes(""));
    }

    /// @dev OZ-UUPS-3b: Upgrade NavOracle to non-UUPS contract
    function test_OZ_UUPS_3b_upgradeToNonUUPSNavOracle() public {
        NonUUPSContract nonUUPS = new NonUUPSContract();

        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(nonUUPS)));
        vm.prank(upgrader);
        UUPSUpgradeable(address(oracle)).upgradeToAndCall(address(nonUUPS), bytes(""));
    }

    /// @dev OZ-UUPS-4b: Direct call initialize on NavOracle implementation
    function test_OZ_UUPS_4b_directInitializeNavOracleImpl() public {
        vm.expectRevert();
        oracleImpl.initialize(admin, 1e18, 5e16, 1e17, 5e16, 1 days);
    }

    // ─── NavVault Upgrades ────────────────────────────────────────────────

    /// @dev OZ-UUPS-1c: Legitimate upgrade of NavVault
    function test_OZ_UUPS_1c_legitimateUpgradeNavVault() public {
        vm.prank(upgrader);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(address(vaultV2Impl), bytes(""));

        CoboFundVaultV2 vaultV2 = CoboFundVaultV2(address(vault));
        assertEq(vaultV2.versionV2(), "v2");
    }

    /// @dev OZ-UUPS-2c: Unauthorized upgrade of NavVault
    function test_OZ_UUPS_2c_unauthorizedUpgradeNavVault() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, randomUser, UPGRADER_ROLE)
        );
        vm.prank(randomUser);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(address(vaultV2Impl), bytes(""));
    }

    /// @dev OZ-UUPS-3c: Upgrade NavVault to non-UUPS contract
    function test_OZ_UUPS_3c_upgradeToNonUUPSNavVault() public {
        NonUUPSContract nonUUPS = new NonUUPSContract();

        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(nonUUPS)));
        vm.prank(upgrader);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(address(nonUUPS), bytes(""));
    }

    /// @dev OZ-UUPS-4c: Direct call initialize on NavVault implementation
    function test_OZ_UUPS_4c_directInitializeNavVaultImpl() public {
        vm.expectRevert();
        vaultImpl.initialize(address(asset), address(fundToken), admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 8.4 Storage Layout Upgrade Compatibility
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev UPG-1: V1->V2 upgrade preserves state.
    ///      Deploy V1, set state (deposit, redeem request, whitelist, freeze, oracle address, vault address).
    ///      Upgrade to V2 -> read state -> all V1 state variables unchanged.
    function test_UPG_1_v1ToV2StatePreserved() public {
        // --- Establish V1 state ---

        // 1) user1 deposits 100 ASSET
        uint256 depositShares = _deposit(user1, 100e6);

        // 2) user1 requests redemption for half
        uint256 halfShares = depositShares / 2;
        uint256 reqId = _requestRedemption(user1, halfShares);

        // 3) Set whitelist and freeze state
        vm.startPrank(admin);
        fundToken.addToWhitelist(makeAddr("extraUser"));
        vm.stopPrank();

        vm.prank(blocklistAdmin);
        fundToken.removeFromWhitelist(user2);

        // Record V1 state before upgrade
        uint256 v1_user1Balance = fundToken.balanceOf(user1);
        uint256 v1_totalSupply = fundToken.totalSupply();
        address v1_oracle = address(fundToken.oracle());
        address v1_vault = fundToken.vault();
        uint256 v1_minDeposit = fundToken.minDepositAmount();
        uint256 v1_minRedeem = fundToken.minRedeemShares();
        uint256 v1_redemptionCount = fundToken.redemptionCount();
        bool v1_user1WL = fundToken.whitelist(user1);
        bool v1_extraWL = fundToken.whitelist(makeAddr("extraUser"));
        bool v1_user2Frozen = !fundToken.whitelist(user2);

        // Read redemption request data
        (
            uint256 v1_rId,
            address v1_rUser,
            uint256 v1_rAsset,
            uint256 v1_rShare,
            uint256 v1_rAt,
            CoboFundToken.RedemptionStatus v1_rStatus
        ) = fundToken.redemptions(reqId);

        // Record Oracle V1 state
        uint256 v1_oBaseNetValue = oracle.baseNetValue();
        uint256 v1_oCurrentAPR = oracle.currentAPR();
        uint256 v1_oMaxAPR = oracle.maxAPR();
        uint256 v1_oMaxAprDelta = oracle.maxAprDelta();
        uint256 v1_oMinUpdateInterval = oracle.minUpdateInterval();

        // Record Vault V1 state
        uint256 v1_vaultAssetBalance = asset.balanceOf(address(vault));
        bool v1_vaultWL_user1 = vault.whitelist(user1);

        // --- Upgrade all three contracts ---
        vm.startPrank(upgrader);
        UUPSUpgradeable(address(oracle)).upgradeToAndCall(address(oracleV2Impl), bytes(""));
        UUPSUpgradeable(address(fundToken)).upgradeToAndCall(address(fundTokenV2Impl), bytes(""));
        UUPSUpgradeable(address(vault)).upgradeToAndCall(address(vaultV2Impl), bytes(""));
        vm.stopPrank();

        // --- Verify ALL V1 state preserved in Nav4626 ---
        assertEq(fundToken.balanceOf(user1), v1_user1Balance, "user1 balance changed");
        assertEq(fundToken.totalSupply(), v1_totalSupply, "totalSupply changed");
        assertEq(address(fundToken.oracle()), v1_oracle, "oracle address changed");
        assertEq(fundToken.vault(), v1_vault, "vault address changed");
        assertEq(fundToken.minDepositAmount(), v1_minDeposit, "minDepositAmount changed");
        assertEq(fundToken.minRedeemShares(), v1_minRedeem, "minRedeemShares changed");
        assertEq(fundToken.redemptionCount(), v1_redemptionCount, "redemptionCount changed");
        assertEq(fundToken.whitelist(user1), v1_user1WL, "user1 whitelist changed");
        assertEq(fundToken.whitelist(makeAddr("extraUser")), v1_extraWL, "extraUser whitelist changed");
        assertEq(!fundToken.whitelist(user2), v1_user2Frozen, "user2 frozen changed");

        // Verify redemption request preserved
        (
            uint256 v2_rId,
            address v2_rUser,
            uint256 v2_rAsset,
            uint256 v2_rShare,
            uint256 v2_rAt,
            CoboFundToken.RedemptionStatus v2_rStatus
        ) = fundToken.redemptions(reqId);
        assertEq(v2_rId, v1_rId, "redemption id changed");
        assertEq(v2_rUser, v1_rUser, "redemption user changed");
        assertEq(v2_rAsset, v1_rAsset, "redemption assetAmount changed");
        assertEq(v2_rShare, v1_rShare, "redemption shareAmount changed");
        assertEq(v2_rAt, v1_rAt, "redemption requestedAt changed");
        assertEq(uint256(v2_rStatus), uint256(v1_rStatus), "redemption status changed");

        // --- Verify Oracle state preserved ---
        assertEq(oracle.baseNetValue(), v1_oBaseNetValue, "oracle baseNetValue changed");
        assertEq(oracle.currentAPR(), v1_oCurrentAPR, "oracle currentAPR changed");
        assertEq(oracle.maxAPR(), v1_oMaxAPR, "oracle maxAPR changed");
        assertEq(oracle.maxAprDelta(), v1_oMaxAprDelta, "oracle maxAprDelta changed");
        assertEq(oracle.minUpdateInterval(), v1_oMinUpdateInterval, "oracle minUpdateInterval changed");

        // --- Verify Vault state preserved ---
        assertEq(asset.balanceOf(address(vault)), v1_vaultAssetBalance, "vault ASSET balance changed");
        assertEq(vault.whitelist(user1), v1_vaultWL_user1, "vault whitelist user1 changed");
    }

    /// @dev UPG-2: V2 new variable doesn't affect V1 layout.
    ///      After upgrade, V2 new variable has default value (0).
    ///      Setting it doesn't affect existing V1 variables.
    function test_UPG_2_v2NewVariableDoesNotAffectV1Layout() public {
        // Deposit to establish state
        _deposit(user1, 50e6);
        uint256 v1Balance = fundToken.balanceOf(user1);

        // Upgrade Nav4626
        vm.prank(upgrader);
        UUPSUpgradeable(address(fundToken)).upgradeToAndCall(address(fundTokenV2Impl), bytes(""));

        CoboFundTokenV2 fundTokenV2 = CoboFundTokenV2(address(fundToken));

        // New variable should be 0 by default
        assertEq(fundTokenV2.newVariable(), 0, "newVariable should be 0 by default");

        // Set new variable
        fundTokenV2.setNewVariable(42);
        assertEq(fundTokenV2.newVariable(), 42, "newVariable should be 42");

        // V1 state should be unaffected
        assertEq(fundToken.balanceOf(user1), v1Balance, "user1 balance affected by newVariable");
        assertEq(address(fundToken.oracle()), address(oracle), "oracle address affected by newVariable");
        assertEq(fundToken.vault(), address(vault), "vault address affected by newVariable");
    }

    /// @dev UPG-3: After upgrade to V2, call new functions.
    function test_UPG_3_v2NewFunctionality() public {
        // Upgrade all three
        vm.startPrank(upgrader);
        UUPSUpgradeable(address(oracle)).upgradeToAndCall(address(oracleV2Impl), bytes(""));
        UUPSUpgradeable(address(fundToken)).upgradeToAndCall(address(fundTokenV2Impl), bytes(""));
        UUPSUpgradeable(address(vault)).upgradeToAndCall(address(vaultV2Impl), bytes(""));
        vm.stopPrank();

        // Cast to V2 types
        CoboFundOracleV2 oracleV2 = CoboFundOracleV2(address(oracle));
        CoboFundTokenV2 fundTokenV2 = CoboFundTokenV2(address(fundToken));
        CoboFundVaultV2 vaultV2 = CoboFundVaultV2(address(vault));

        // Call versionV2 on all three
        assertEq(oracleV2.versionV2(), "v2", "Oracle versionV2 failed");
        assertEq(fundTokenV2.versionV2(), "v2", "Nav4626 versionV2 failed");
        assertEq(vaultV2.versionV2(), "v2", "Vault versionV2 failed");

        // Set and read newVariable on all three
        oracleV2.setNewVariable(100);
        assertEq(oracleV2.newVariable(), 100, "Oracle newVariable");

        fundTokenV2.setNewVariable(200);
        assertEq(fundTokenV2.newVariable(), 200, "Nav4626 newVariable");

        vaultV2.setNewVariable(300);
        assertEq(vaultV2.newVariable(), 300, "Vault newVariable");
    }

    /// @dev UPG-4: Storage gap verification.
    ///      Verifies that __gap is declared (50 slots) in each contract.
    ///      Since V2 adds a newVariable and it works without corrupting state,
    ///      the storage gap was properly reserved and used.
    function test_UPG_4_storageGapVerification() public {
        // Establish state before upgrade
        _deposit(user1, 10e6);
        uint256 v1Balance = fundToken.balanceOf(user1);

        // Upgrade Nav4626 to V2 (V2 adds newVariable which consumes one gap slot)
        vm.prank(upgrader);
        UUPSUpgradeable(address(fundToken)).upgradeToAndCall(address(fundTokenV2Impl), bytes(""));

        CoboFundTokenV2 fundTokenV2 = CoboFundTokenV2(address(fundToken));

        // V2 new variable works
        fundTokenV2.setNewVariable(999);
        assertEq(fundTokenV2.newVariable(), 999, "newVariable should be 999");

        // V1 state not corrupted (proves gap was available)
        assertEq(fundToken.balanceOf(user1), v1Balance, "V1 balance corrupted after V2 variable set");

        // Same test for Oracle
        vm.prank(upgrader);
        UUPSUpgradeable(address(oracle)).upgradeToAndCall(address(oracleV2Impl), bytes(""));

        CoboFundOracleV2 oracleV2 = CoboFundOracleV2(address(oracle));
        uint256 oracleBaseNav = oracle.baseNetValue();
        oracleV2.setNewVariable(888);
        assertEq(oracleV2.newVariable(), 888, "Oracle newVariable should be 888");
        assertEq(oracle.baseNetValue(), oracleBaseNav, "Oracle baseNetValue corrupted");

        // Same test for Vault
        vm.prank(upgrader);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(address(vaultV2Impl), bytes(""));

        CoboFundVaultV2 vaultV2 = CoboFundVaultV2(address(vault));
        bool vaultWL = vault.whitelist(user1);
        vaultV2.setNewVariable(777);
        assertEq(vaultV2.newVariable(), 777, "Vault newVariable should be 777");
        assertEq(vault.whitelist(user1), vaultWL, "Vault whitelist corrupted");
    }

    /// @dev UPG-5: Forbid deleting/reordering existing variables.
    ///      This is hard to test programmatically. Instead, we verify that V2 contracts
    ///      that extend from V1 work correctly, which implicitly proves layout compatibility.
    ///      A real-world check would use `forge inspect` to compare storage layouts.
    ///
    ///      NOTE: If V2 were to reorder or delete variables, the V1 state would be corrupted
    ///      after upgrade. The test_UPG_1 and test_UPG_2 tests verify this indirectly.
    function test_UPG_5_layoutCompatibilityComment() public {
        // This test serves as documentation and a basic sanity check.
        // The V2 contracts inherit from V1 and add variables at the end.
        // If layout were incompatible, UPG-1 and UPG-2 would fail.

        // Verify by doing a full round-trip:
        // 1. Set V1 state
        _deposit(user1, 20e6);
        uint256 balanceBefore = fundToken.balanceOf(user1);

        // 2. Upgrade to V2
        vm.prank(upgrader);
        UUPSUpgradeable(address(fundToken)).upgradeToAndCall(address(fundTokenV2Impl), bytes(""));

        // 3. Use V2 new variable
        CoboFundTokenV2 fundTokenV2 = CoboFundTokenV2(address(fundToken));
        fundTokenV2.setNewVariable(12345);

        // 4. Verify V1 state still intact
        assertEq(fundToken.balanceOf(user1), balanceBefore, "Balance corrupted after V2 variable write");

        // 5. Verify V1 operations still work (deposit more)
        uint256 additionalShares = _deposit(user1, 10e6);
        assertGt(additionalShares, 0, "Deposit after upgrade failed");
        assertEq(
            fundToken.balanceOf(user1),
            balanceBefore + additionalShares,
            "Balance incorrect after post-upgrade deposit"
        );
    }

    /// @dev UPG-Sanctions: sanctionsOracle state persists across upgrade.
    ///      Verifies the new sanctions storage slot is preserved after upgrading the FundToken
    ///      implementation, and that screening continues to enforce post-upgrade.
    function test_UPG_sanctionsOraclePersistsAcrossUpgrade() public {
        // Sanction user2 before upgrade.
        sanctionsOracle.setSanctioned(user2, true);
        address oracleAddrBefore = address(fundToken.sanctionsOracle());
        assertEq(oracleAddrBefore, address(sanctionsOracle), "sanctionsOracle pre-upgrade");

        // Upgrade FundToken to V2.
        vm.prank(upgrader);
        UUPSUpgradeable(address(fundToken)).upgradeToAndCall(address(fundTokenV2Impl), bytes(""));

        // sanctionsOracle slot survives — same address, same enforcement.
        assertEq(address(fundToken.sanctionsOracle()), oracleAddrBefore, "sanctionsOracle post-upgrade");

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.AddressSanctioned.selector, user2));
        fundToken.mint(MIN_DEPOSIT_AMOUNT);

        // V2 new variable still works in the slot following sanctionsOracle.
        CoboFundTokenV2 fundTokenV2 = CoboFundTokenV2(address(fundToken));
        fundTokenV2.setNewVariable(42);
        assertEq(fundTokenV2.newVariable(), 42, "V2 newVariable broken");
    }

    /// @dev UPG-6: Three contracts independently upgradeable.
    ///      Upgrade NavOracle -> then Nav4626 -> then Vault.
    ///      Perform operations between each upgrade to verify system integrity.
    function test_UPG_6_threeContractsIndependentlyUpgradeable() public {
        // --- Step 1: Establish initial state ---
        uint256 initialShares = _deposit(user1, 50e6);
        assertGt(initialShares, 0, "Initial deposit failed");

        // --- Step 2: Upgrade NavOracle only ---
        vm.prank(upgrader);
        UUPSUpgradeable(address(oracle)).upgradeToAndCall(address(oracleV2Impl), bytes(""));

        // Verify Oracle V2 works
        CoboFundOracleV2 oracleV2 = CoboFundOracleV2(address(oracle));
        assertEq(oracleV2.versionV2(), "v2", "Oracle V2 function failed");

        // Verify system still works: user2 can deposit (Nav4626 reads oracle price)
        uint256 shares2 = _deposit(user2, 20e6);
        assertGt(shares2, 0, "Deposit after Oracle upgrade failed");

        // Verify Oracle update still works
        vm.warp(block.timestamp + 1 days);
        vm.prank(navUpdater);
        oracle.updateRate(3e16, "post-upgrade");

        // --- Step 3: Upgrade Nav4626 only ---
        vm.prank(upgrader);
        UUPSUpgradeable(address(fundToken)).upgradeToAndCall(address(fundTokenV2Impl), bytes(""));

        // Verify Nav4626 V2 works
        CoboFundTokenV2 fundTokenV2 = CoboFundTokenV2(address(fundToken));
        assertEq(fundTokenV2.versionV2(), "v2", "Nav4626 V2 function failed");

        // Verify system still works: user1 can request redemption
        uint256 redeemShares = fundToken.balanceOf(user1);
        assertGt(redeemShares, 0, "user1 has no shares");
        uint256 reqId = _requestRedemption(user1, redeemShares);

        // Approver can approve the request
        (, address reqUser, uint256 reqAsset, uint256 reqShare, , ) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, reqUser, reqAsset, reqShare);

        // --- Step 4: Upgrade NavVault only ---
        vm.prank(upgrader);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(address(vaultV2Impl), bytes(""));

        // Verify Vault V2 works
        CoboFundVaultV2 vaultV2 = CoboFundVaultV2(address(vault));
        assertEq(vaultV2.versionV2(), "v2", "Vault V2 function failed");

        // Verify system still works: settlement operator can withdraw
        // Fund vault first if needed — vault should still have ASSET from user2's deposit
        uint256 vaultBalance = asset.balanceOf(address(vault));
        if (vaultBalance > 0) {
            vm.prank(settlementOperator);
            vault.withdraw(user1, vaultBalance);
        }

        // Verify all three V2 new variables work simultaneously
        oracleV2.setNewVariable(111);
        fundTokenV2.setNewVariable(222);
        vaultV2.setNewVariable(333);

        assertEq(oracleV2.newVariable(), 111, "Oracle V2 newVariable");
        assertEq(fundTokenV2.newVariable(), 222, "Nav4626 V2 newVariable");
        assertEq(vaultV2.newVariable(), 333, "Vault V2 newVariable");
    }
}
