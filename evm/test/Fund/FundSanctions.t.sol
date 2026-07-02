// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "./FundTestBase.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {CoboFundToken} from "../../src/Fund/CoboFundToken.sol";
import {MockSanctionsOracle} from "./mocks/MockSanctionsOracle.sol";

contract FundSanctionsTest is FundTestBase {
    // ─── Events (mirrored from CoboFundToken) ───────────────────────────
    event SanctionsOracleUpdated(address indexed newOracle);
    event RedemptionForfeited(
        uint256 indexed reqId,
        address indexed user,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 timestamp,
        address forfeitedBy
    );

    // ═════════════════════════════════════════════════════════════════════
    //  Oracle configuration
    // ═════════════════════════════════════════════════════════════════════

    function test_setSanctionsOracle_admin() public {
        MockSanctionsOracle newOracle = new MockSanctionsOracle();

        vm.expectEmit(true, false, false, false);
        emit SanctionsOracleUpdated(address(newOracle));

        vm.prank(admin);
        fundToken.setSanctionsOracle(address(newOracle));

        assertEq(address(fundToken.sanctionsOracle()), address(newOracle));
    }

    function test_setSanctionsOracle_nonAdmin_reverts() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, DEFAULT_ADMIN_ROLE)
        );
        fundToken.setSanctionsOracle(address(0xdead));
    }

    function test_setSanctionsOracle_reenableAfterDisable() public {
        // Disable.
        vm.prank(admin);
        fundToken.setSanctionsOracle(address(0));
        assertEq(address(fundToken.sanctionsOracle()), address(0));

        // Sanctioned user can mint during disable.
        sanctionsOracle.setSanctioned(user1, true);
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);

        // Re-enable with a fresh oracle that also marks user1 sanctioned.
        MockSanctionsOracle newOracle = new MockSanctionsOracle();
        newOracle.setSanctioned(user1, true);
        vm.prank(admin);
        fundToken.setSanctionsOracle(address(newOracle));
        assertEq(address(fundToken.sanctionsOracle()), address(newOracle));

        // Enforcement resumes: user1 is blocked again.
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.AddressSanctioned.selector, user1));
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
    }

    function test_setSanctionsOracle_rejectsMaliciousOracle() public {
        // A pathological oracle that returns true for ALL addresses (incl. the token contract
        // itself) would deadlock every transfer if installed. The setter's sanity check
        // (isSanctioned(self) must be false) blocks this.
        MockSanctionsOracle evilOracle = new MockSanctionsOracle();
        evilOracle.setSanctioned(address(fundToken), true);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(LibFundErrors.InvalidSanctionsOracle.selector, address(evilOracle))
        );
        fundToken.setSanctionsOracle(address(evilOracle));

        // sanctionsOracle remains the original (set up in FundTestBase).
        assertEq(address(fundToken.sanctionsOracle()), address(sanctionsOracle));
    }

    function test_setSanctionsOracle_rejectsNonOracleContract() public {
        // A non-conforming contract (e.g. EOA stub, or contract without isSanctioned) makes the
        // sanity-check staticcall revert; setter must propagate that failure rather than write
        // a broken oracle reference.
        vm.prank(admin);
        vm.expectRevert();
        fundToken.setSanctionsOracle(address(asset)); // asset is an ERC20, has no isSanctioned()
    }

    function test_setSanctionsOracle_zeroAddress_disablesScreening() public {
        // Sanction user1 with the current oracle to confirm enforcement is active.
        sanctionsOracle.setSanctioned(user1, true);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.AddressSanctioned.selector, user1));
        fundToken.mint(MIN_DEPOSIT_AMOUNT);

        // Clear oracle address → screening disabled.
        vm.prank(admin);
        fundToken.setSanctionsOracle(address(0));

        // mint now succeeds despite user1 still being on the (now-disconnected) list.
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  mint enforcement
    // ═════════════════════════════════════════════════════════════════════

    function test_mint_blocksSanctionedSender() public {
        sanctionsOracle.setSanctioned(user1, true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.AddressSanctioned.selector, user1));
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
    }

    function test_mint_succeedsWhenNotSanctioned() public {
        // user1 is whitelisted but never sanctioned → mint works.
        vm.prank(user1);
        uint256 shares = fundToken.mint(MIN_DEPOSIT_AMOUNT);
        assertGt(shares, 0);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  requestRedemption enforcement
    // ═════════════════════════════════════════════════════════════════════

    function test_requestRedemption_blocksSanctionedSender() public {
        // user1 mints first while still clean.
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);

        // Now sanction user1 — they can no longer request redemption.
        sanctionsOracle.setSanctioned(user1, true);

        uint256 shareBalance = fundToken.balanceOf(user1);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.AddressSanctioned.selector, user1));
        fundToken.requestRedemption(shareBalance);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  approveRedemption enforcement
    // ═════════════════════════════════════════════════════════════════════

    function test_approveRedemption_blocksUserSanctionedAfterRequest() public {
        // user1 mints + requests redemption while clean.
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
        uint256 shareBalance = fundToken.balanceOf(user1);

        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(shareBalance);

        (, , uint256 assetAmount, uint256 storedShare, , ) = fundToken.redemptions(reqId);

        // After request but before approve, user1 is listed.
        sanctionsOracle.setSanctioned(user1, true);

        // Vault must hold enough asset and approve the FundToken to attempt payout.
        // (Already pre-approved via initializer.) Approve should now revert.
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.AddressSanctioned.selector, user1));
        fundToken.approveRedemption(reqId, user1, assetAmount, storedShare);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  rejectRedemption enforcement (per client requirement)
    // ═════════════════════════════════════════════════════════════════════

    function test_rejectRedemption_blocksUserSanctionedAfterRequest() public {
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
        uint256 shareBalance = fundToken.balanceOf(user1);

        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(shareBalance);
        (, , uint256 assetAmount, uint256 storedShare, , ) = fundToken.redemptions(reqId);

        sanctionsOracle.setSanctioned(user1, true);

        // Both approve AND reject must revert → request becomes stuck.
        vm.prank(redemptionApprover);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.AddressSanctioned.selector, user1));
        fundToken.rejectRedemption(reqId, user1, assetAmount, storedShare);
    }

    function test_rejectRedemption_succeedsForCleanUser() public {
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
        uint256 shareBalance = fundToken.balanceOf(user1);

        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(shareBalance);
        (, , uint256 assetAmount, uint256 storedShare, , ) = fundToken.redemptions(reqId);

        vm.prank(redemptionApprover);
        fundToken.rejectRedemption(reqId, user1, assetAmount, storedShare);

        // Shares restored.
        assertEq(fundToken.balanceOf(user1), shareBalance);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  _update hook enforcement (share secondary-market transfers)
    // ═════════════════════════════════════════════════════════════════════

    function test_transfer_blocksSanctionedSender() public {
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);

        sanctionsOracle.setSanctioned(user1, true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.AddressSanctioned.selector, user1));
        fundToken.transfer(user2, 1);
    }

    function test_transfer_blocksSanctionedRecipient() public {
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);

        sanctionsOracle.setSanctioned(user2, true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.AddressSanctioned.selector, user2));
        fundToken.transfer(user2, 1);
    }

    function test_transfer_allowedWhenBothClean() public {
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);

        uint256 amount = fundToken.balanceOf(user1) / 2;
        vm.prank(user1);
        fundToken.transfer(user2, amount);

        assertEq(fundToken.balanceOf(user2), amount);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Vault.withdraw enforcement
    // ═════════════════════════════════════════════════════════════════════

    function test_vaultWithdraw_blocksSanctionedRecipient() public {
        // user1 mints so Vault holds asset.
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT * 10);

        // user2 is the settlement target — sanction it.
        sanctionsOracle.setSanctioned(user2, true);

        vm.prank(settlementOperator);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.AddressSanctioned.selector, user2));
        vault.withdraw(user2, MIN_DEPOSIT_AMOUNT);
    }

    function test_vaultWithdraw_allowedWhenRecipientClean() public {
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT * 10);

        vm.prank(settlementOperator);
        vault.withdraw(user2, MIN_DEPOSIT_AMOUNT);

        assertEq(asset.balanceOf(user2), 1000e6 + MIN_DEPOSIT_AMOUNT); // initial 1000 + withdrawn
    }

    function test_vaultWithdraw_bypassesWhenOracleUnset() public {
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT * 10);

        // Sanction the target.
        sanctionsOracle.setSanctioned(user2, true);

        // Disable screening by clearing the oracle.
        vm.prank(admin);
        fundToken.setSanctionsOracle(address(0));

        // Withdraw now succeeds (screening bypassed via address(0) oracle).
        vm.prank(settlementOperator);
        vault.withdraw(user2, MIN_DEPOSIT_AMOUNT);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  forceRedeem MUST work on sanctioned users (compliance disposal tool)
    // ═════════════════════════════════════════════════════════════════════

    function test_forceRedeem_succeedsOnSanctionedUser() public {
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);

        sanctionsOracle.setSanctioned(user1, true);

        // forceRedeem uses _burnBypass → must succeed even when user is sanctioned.
        vm.prank(admin);
        fundToken.forceRedeem(user1, type(uint256).max);

        assertEq(fundToken.balanceOf(user1), 0);
        assertEq(fundToken.totalSupply(), 0);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  adminForfeitPending for stuck requests
    // ═════════════════════════════════════════════════════════════════════

    function test_adminForfeitPending_forfeitsStuckRequest() public {
        // user1 mints + requests redemption while clean.
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
        uint256 shareBalance = fundToken.balanceOf(user1);

        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(shareBalance);
        uint256 totalPendingBefore = fundToken.totalPendingAssets();
        assertGt(totalPendingBefore, 0);

        // user1 now listed → both approve and reject revert.
        sanctionsOracle.setSanctioned(user1, true);

        // Admin force-clears the stuck request.
        (, , uint256 assetAmount, uint256 storedShare, , ) = fundToken.redemptions(reqId);
        vm.expectEmit(true, true, false, true);
        emit RedemptionForfeited(reqId, user1, assetAmount, storedShare, block.timestamp, admin);

        vm.prank(admin);
        fundToken.adminForfeitPending(reqId);

        // Pending accounting released.
        assertEq(fundToken.totalPendingAssets(), totalPendingBefore - assetAmount);

        // Status flipped to Rejected.
        (, , , , , CoboFundToken.RedemptionStatus status) = fundToken.redemptions(reqId);
        assertEq(uint8(status), uint8(CoboFundToken.RedemptionStatus.Rejected));

        // Shares NOT minted back — user1 balance remains 0.
        assertEq(fundToken.balanceOf(user1), 0);
    }

    function test_adminForfeitPending_nonAdmin_reverts() public {
        // Create a Pending request first.
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
        uint256 shareBalance = fundToken.balanceOf(user1);
        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(shareBalance);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, DEFAULT_ADMIN_ROLE)
        );
        fundToken.adminForfeitPending(reqId);
    }

    function test_adminForfeitPending_invalidReqId_reverts() public {
        // No request exists at id 999.
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.InvalidRedemptionRequest.selector, 999));
        fundToken.adminForfeitPending(999);
    }

    function test_adminForfeitPending_alreadySettled_reverts() public {
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
        uint256 shareBalance = fundToken.balanceOf(user1);
        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(shareBalance);
        (, , uint256 assetAmount, uint256 storedShare, , ) = fundToken.redemptions(reqId);

        // Normal approval first.
        vm.prank(redemptionApprover);
        fundToken.approveRedemption(reqId, user1, assetAmount, storedShare);

        // Now force-clear must revert (not Pending anymore).
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(LibFundErrors.RedemptionNotPending.selector, reqId));
        fundToken.adminForfeitPending(reqId);
    }

    function test_adminForfeitPending_whilePaused() public {
        // Set up a stuck pending request (user listed after request).
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
        uint256 shareBalance = fundToken.balanceOf(user1);
        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(shareBalance);
        sanctionsOracle.setSanctioned(user1, true);

        // Pause the system.
        vm.prank(admin);
        fundToken.pause();
        assertTrue(fundToken.paused());

        // adminForfeitPending must still work — it is a compliance disposal tool that
        // intentionally has no `whenNotPaused` modifier (parallels forceRedeem).
        (, , uint256 assetAmount, uint256 storedShare, , ) = fundToken.redemptions(reqId);
        uint256 totalPendingBefore = fundToken.totalPendingAssets();

        vm.prank(admin);
        fundToken.adminForfeitPending(reqId);

        assertEq(fundToken.totalPendingAssets(), totalPendingBefore - assetAmount);
        (, , , , , CoboFundToken.RedemptionStatus status) = fundToken.redemptions(reqId);
        assertEq(uint8(status), uint8(CoboFundToken.RedemptionStatus.Rejected));
        // silence: storedShare is read for storage layout symmetry with sibling tests
        storedShare;
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Oracle revert is treated as fail-close (no silent bypass)
    // ═════════════════════════════════════════════════════════════════════

    function test_oracleRevert_failsClosed_mint() public {
        sanctionsOracle.setShouldRevert(true);

        vm.prank(user1);
        vm.expectRevert(bytes("MockSanctionsOracle: revert"));
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
    }

    function test_oracleRevert_failsClosed_transfer() public {
        // Mint while clean so user1 has shares.
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);

        // Now make oracle revert on every call.
        sanctionsOracle.setShouldRevert(true);

        vm.prank(user1);
        vm.expectRevert(bytes("MockSanctionsOracle: revert"));
        fundToken.transfer(user2, 1);
    }

    function test_oracleRevert_failsClosed_requestRedemption() public {
        // Set up shares while clean.
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
        uint256 shareBalance = fundToken.balanceOf(user1);

        sanctionsOracle.setShouldRevert(true);

        vm.prank(user1);
        vm.expectRevert(bytes("MockSanctionsOracle: revert"));
        fundToken.requestRedemption(shareBalance);
    }

    function test_oracleRevert_failsClosed_approveRedemption() public {
        // Set up a pending request while oracle is clean.
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
        uint256 shareBalance = fundToken.balanceOf(user1);
        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(shareBalance);
        (, , uint256 assetAmount, uint256 storedShare, , ) = fundToken.redemptions(reqId);

        sanctionsOracle.setShouldRevert(true);

        vm.prank(redemptionApprover);
        vm.expectRevert(bytes("MockSanctionsOracle: revert"));
        fundToken.approveRedemption(reqId, user1, assetAmount, storedShare);
    }

    function test_oracleRevert_failsClosed_rejectRedemption() public {
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT);
        uint256 shareBalance = fundToken.balanceOf(user1);
        vm.prank(user1);
        uint256 reqId = fundToken.requestRedemption(shareBalance);
        (, , uint256 assetAmount, uint256 storedShare, , ) = fundToken.redemptions(reqId);

        sanctionsOracle.setShouldRevert(true);

        vm.prank(redemptionApprover);
        vm.expectRevert(bytes("MockSanctionsOracle: revert"));
        fundToken.rejectRedemption(reqId, user1, assetAmount, storedShare);
    }

    function test_oracleRevert_failsClosed_vaultWithdraw() public {
        // Vault needs assets to attempt withdraw.
        vm.prank(user1);
        fundToken.mint(MIN_DEPOSIT_AMOUNT * 10);

        sanctionsOracle.setShouldRevert(true);

        vm.prank(settlementOperator);
        vm.expectRevert(bytes("MockSanctionsOracle: revert"));
        vault.withdraw(user2, MIN_DEPOSIT_AMOUNT);
    }
}
