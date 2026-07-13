// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {CoboERC20} from "../src/CoboERC20/CoboERC20.sol";
import {LibErrors} from "../src/CoboERC20/library/Errors/LibErrors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockSanctionsOracle} from "./Fund/mocks/MockSanctionsOracle.sol";
import {MockERC20} from "./Fund/mocks/MockERC20.sol";

/// @dev Sanctions screening enforcement and emergency controls for {CoboERC20}.
contract CoboERC20SanctionsTest is Test {
    CoboERC20 token;
    MockSanctionsOracle oracle;

    address admin = makeAddr("admin");
    address manager = makeAddr("manager");
    address minter = makeAddr("minter");
    address burner = makeAddr("burner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address spender = makeAddr("spender");

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 constant BURNER_ROLE = keccak256("BURNER_ROLE");

    uint256 constant AMOUNT = 1000e18;

    event SanctionsOracleUpdated(address indexed newOracle);

    function setUp() public {
        CoboERC20 logic = new CoboERC20();
        token = CoboERC20(address(new ERC1967Proxy(address(logic), "")));
        token.initialize("Cobo", "COBO", "https://cobo.com", 18, admin);

        vm.startPrank(admin);
        token.grantRole(MANAGER_ROLE, manager);
        token.grantRole(MINTER_ROLE, minter);
        token.grantRole(BURNER_ROLE, burner);
        vm.stopPrank();

        oracle = new MockSanctionsOracle();
        vm.prank(admin);
        token.setSanctionsOracle(address(oracle));
    }

    function _mint(address to, uint256 amount) internal {
        vm.prank(minter);
        token.mint(to, amount);
    }

    // ─── Oracle configuration ───────────────────────────────────────────

    function test_setSanctionsOracle_admin() public {
        MockSanctionsOracle newOracle = new MockSanctionsOracle();

        vm.expectEmit(true, false, false, false);
        emit SanctionsOracleUpdated(address(newOracle));

        vm.prank(admin);
        token.setSanctionsOracle(address(newOracle));

        assertEq(address(token.sanctionsOracle()), address(newOracle));
    }

    function test_setSanctionsOracle_nonAdmin_reverts() public {
        // MANAGER_ROLE (which manages AccessList/BlockList) is NOT enough — this is admin-gated.
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                manager,
                DEFAULT_ADMIN_ROLE
            )
        );
        token.setSanctionsOracle(address(0xdead));
    }

    function test_setSanctionsOracle_installsOracleFlaggingTokenItself() public {
        // The install probe calls isSanctioned but ignores the result, so an oracle that flags the
        // token contract itself still installs. The token address is never a screened party on normal
        // paths, so user transfers work.
        MockSanctionsOracle o = new MockSanctionsOracle();
        o.setSanctioned(address(token), true);

        vm.prank(admin);
        token.setSanctionsOracle(address(o));
        assertEq(address(token.sanctionsOracle()), address(o));

        _mint(alice, AMOUNT);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1e18));
    }

    function test_setSanctionsOracle_nonOracleContract_revertsAtInstall() public {
        // Install-time liveness probe: a non-oracle contract (no isSanctioned) makes the probe
        // call revert, so the candidate is rejected at install rather than stored.
        MockERC20 notAnOracle = new MockERC20("X", "X", 18);
        vm.prank(admin);
        vm.expectRevert();
        token.setSanctionsOracle(address(notAnOracle));

        // Nothing was stored; the previously configured oracle stays in place.
        assertEq(address(token.sanctionsOracle()), address(oracle));
    }

    function test_setSanctionsOracle_eoa_revertsAtInstall() public {
        // An EOA has no code, so the probe call reverts and the candidate is rejected at install.
        vm.prank(admin);
        vm.expectRevert();
        token.setSanctionsOracle(address(0xdead));

        assertEq(address(token.sanctionsOracle()), address(oracle));
    }

    function test_setSanctionsOracle_revertingOracle_revertsAtInstall() public {
        // A conforming oracle that reverts on any query is rejected at install: the probe propagates
        // the revert instead of storing a reference that would freeze every screened transfer.
        MockSanctionsOracle reverting = new MockSanctionsOracle();
        reverting.setShouldRevert(true);

        vm.prank(admin);
        vm.expectRevert();
        token.setSanctionsOracle(address(reverting));

        assertEq(address(token.sanctionsOracle()), address(oracle));
    }

    function test_setSanctionsOracle_zeroAddress_disablesScreening() public {
        oracle.setSanctioned(alice, true);
        _mint(bob, AMOUNT);

        // Screening active: sanctioned recipient blocked.
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, alice));
        token.transfer(alice, 1e18);

        // Disable.
        vm.prank(admin);
        token.setSanctionsOracle(address(0));
        assertEq(address(token.sanctionsOracle()), address(0));

        // Now the transfer to the still-listed address succeeds.
        vm.prank(bob);
        assertTrue(token.transfer(alice, 1e18));
    }

    function test_setSanctionsOracle_reenableAfterDisable() public {
        vm.prank(admin);
        token.setSanctionsOracle(address(0));

        MockSanctionsOracle newOracle = new MockSanctionsOracle();
        newOracle.setSanctioned(alice, true);
        vm.prank(admin);
        token.setSanctionsOracle(address(newOracle));

        _mint(bob, AMOUNT);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, alice));
        token.transfer(alice, 1e18);
    }

    // ─── mint enforcement ────────────────────────────────────────────────

    function test_mint_blocksSanctionedRecipient() public {
        oracle.setSanctioned(alice, true);
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, alice));
        token.mint(alice, AMOUNT);
    }

    function test_mint_succeedsWhenNotSanctioned() public {
        _mint(alice, AMOUNT);
        assertEq(token.balanceOf(alice), AMOUNT);
    }

    // ─── transfer enforcement ──────────────────────────────────────────────

    function test_transfer_blocksSanctionedSender() public {
        _mint(alice, AMOUNT);
        oracle.setSanctioned(alice, true);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, alice));
        token.transfer(bob, 1e18);
    }

    function test_transfer_blocksSanctionedRecipient() public {
        _mint(alice, AMOUNT);
        oracle.setSanctioned(bob, true);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, bob));
        token.transfer(bob, 1e18);
    }

    function test_transfer_cleanPath() public {
        _mint(alice, AMOUNT);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1e18));
        assertEq(token.balanceOf(bob), 1e18);
    }

    // ─── transferFrom enforcement ──────────────────────────────────────────

    function test_transferFrom_blocksSanctionedFrom() public {
        _mint(alice, AMOUNT);
        vm.prank(alice);
        token.approve(spender, AMOUNT);
        oracle.setSanctioned(alice, true);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, alice));
        token.transferFrom(alice, bob, 1e18);
    }

    function test_transferFrom_blocksSanctionedTo() public {
        _mint(alice, AMOUNT);
        vm.prank(alice);
        token.approve(spender, AMOUNT);
        oracle.setSanctioned(bob, true);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, bob));
        token.transferFrom(alice, bob, 1e18);
    }

    function test_transferFrom_blocksSanctionedSpender() public {
        _mint(alice, AMOUNT);
        vm.prank(alice);
        token.approve(spender, AMOUNT);
        oracle.setSanctioned(spender, true);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, spender));
        token.transferFrom(alice, bob, 1e18);
    }

    function test_transferFrom_cleanPath() public {
        _mint(alice, AMOUNT);
        vm.prank(alice);
        token.approve(spender, AMOUNT);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1e18));
        assertEq(token.balanceOf(bob), 1e18);
    }

    // ─── burn paths are NOT screened (compliance seizure) ────────────────

    function test_burnFrom_seizesSanctionedBalance() public {
        _mint(alice, AMOUNT);
        oracle.setSanctioned(alice, true);

        // Seizure via MANAGER_ROLE succeeds despite the holder being sanctioned.
        vm.prank(manager);
        token.burnFrom(alice, AMOUNT);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_burn_notScreened() public {
        _mint(burner, AMOUNT);
        oracle.setSanctioned(burner, true);

        vm.prank(burner);
        token.burn(AMOUNT);
        assertEq(token.balanceOf(burner), 0);
    }

    // ─── fail-close on oracle revert ─────────────────────────────────────

    function test_transfer_failsClosedOnOracleRevert() public {
        _mint(alice, AMOUNT);
        oracle.setShouldRevert(true);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1e18);
    }

    // ─── oracle and BlockList are independent ────────────────────────────

    function test_oracleAndBlockList_independent() public {
        _mint(alice, AMOUNT);

        // Blocked by oracle only (not on BlockList).
        oracle.setSanctioned(bob, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, bob));
        token.transfer(bob, 1e18);

        // Disable oracle; BlockList still blocks.
        oracle.setSanctioned(bob, false);
        vm.prank(admin);
        token.setSanctionsOracle(address(0));

        address[] memory list = new address[](1);
        list[0] = bob;
        vm.prank(manager);
        token.blockListAdd(list);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.BlockedAddress.selector, bob));
        token.transfer(bob, 1e18);
    }

    // ─── default-off: no oracle configured ───────────────────────────────

    function test_defaultOff_freshContractHasNoOracle() public {
        CoboERC20 logic = new CoboERC20();
        CoboERC20 fresh = CoboERC20(address(new ERC1967Proxy(address(logic), "")));
        fresh.initialize("Fresh", "FRSH", "uri", 18, admin);
        vm.prank(admin);
        fresh.grantRole(MINTER_ROLE, minter);

        assertEq(address(fresh.sanctionsOracle()), address(0));

        // Screening is off: minting/transferring works with no oracle set.
        vm.prank(minter);
        fresh.mint(alice, AMOUNT);
        vm.prank(alice);
        assertTrue(fresh.transfer(bob, 1e18));
    }
}
