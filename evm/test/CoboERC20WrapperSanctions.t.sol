// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {CoboERC20Wrapper} from "../src/CoboERC20/CoboERC20Wrapper.sol";
import {LibErrors} from "../src/CoboERC20/library/Errors/LibErrors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockSanctionsOracle} from "./Fund/mocks/MockSanctionsOracle.sol";
import {MockERC20} from "./Fund/mocks/MockERC20.sol";

/// @dev Sanctions screening enforcement for {CoboERC20Wrapper} (deposit / withdraw / mint / transfer).
contract CoboERC20WrapperSanctionsTest is Test {
    CoboERC20Wrapper wrapper;
    MockSanctionsOracle oracle;
    MockERC20 underlying;

    address admin = makeAddr("admin");
    address manager = makeAddr("manager");
    address minter = makeAddr("minter");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 constant WRAPPER_ROLE = keccak256("WRAPPER_ROLE");

    uint256 constant AMOUNT = 1000e18;

    event SanctionsOracleUpdated(address indexed newOracle);

    function setUp() public {
        underlying = new MockERC20("Under", "UND", 18);

        CoboERC20Wrapper logic = new CoboERC20Wrapper();
        wrapper = CoboERC20Wrapper(address(new ERC1967Proxy(address(logic), "")));
        wrapper.initialize(address(underlying), "Wrapped", "wUND", "https://cobo.com", admin);

        vm.startPrank(admin);
        wrapper.grantRole(MANAGER_ROLE, manager);
        wrapper.grantRole(MINTER_ROLE, minter);
        wrapper.grantRole(WRAPPER_ROLE, alice);
        wrapper.grantRole(WRAPPER_ROLE, bob);
        vm.stopPrank();

        oracle = new MockSanctionsOracle();
        vm.prank(admin);
        wrapper.setSanctionsOracle(address(oracle));

        // Fund alice with underlying and approve the wrapper.
        underlying.mint(alice, AMOUNT);
        vm.prank(alice);
        underlying.approve(address(wrapper), type(uint256).max);
    }

    // ─── Oracle configuration ───────────────────────────────────────────

    function test_setSanctionsOracle_admin() public {
        MockSanctionsOracle newOracle = new MockSanctionsOracle();
        vm.expectEmit(true, false, false, false);
        emit SanctionsOracleUpdated(address(newOracle));
        vm.prank(admin);
        wrapper.setSanctionsOracle(address(newOracle));
        assertEq(address(wrapper.sanctionsOracle()), address(newOracle));
    }

    function test_setSanctionsOracle_nonAdmin_reverts() public {
        // MANAGER_ROLE is NOT enough — this is admin-gated.
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                manager,
                DEFAULT_ADMIN_ROLE
            )
        );
        wrapper.setSanctionsOracle(address(0xdead));
    }

    function test_setSanctionsOracle_installsOracleFlaggingWrapperItself() public {
        // The install probe calls isSanctioned but ignores the result, so a conforming oracle that
        // flags the wrapper contract itself installs fine. deposit screens the sender (alice), not
        // the wrapper address, so it still works.
        MockSanctionsOracle o = new MockSanctionsOracle();
        o.setSanctioned(address(wrapper), true);
        vm.prank(admin);
        wrapper.setSanctionsOracle(address(o));
        assertEq(address(wrapper.sanctionsOracle()), address(o));

        vm.prank(alice);
        assertTrue(wrapper.deposit(AMOUNT));
    }

    function test_setSanctionsOracle_nonOracleContract_revertsAtInstall() public {
        // Install-time liveness probe: a non-oracle contract (no isSanctioned) makes the probe
        // call revert, so the candidate is rejected at install rather than stored.
        MockERC20 notAnOracle = new MockERC20("X", "X", 18);
        vm.prank(admin);
        vm.expectRevert();
        wrapper.setSanctionsOracle(address(notAnOracle));

        // Nothing was stored; the previously configured oracle stays in place.
        assertEq(address(wrapper.sanctionsOracle()), address(oracle));
    }

    function test_setSanctionsOracle_revertingOracle_revertsAtInstall() public {
        // A conforming oracle that reverts on any query is rejected at install: the probe propagates
        // the revert instead of storing a reference that would freeze every screened transfer.
        MockSanctionsOracle reverting = new MockSanctionsOracle();
        reverting.setShouldRevert(true);

        vm.prank(admin);
        vm.expectRevert();
        wrapper.setSanctionsOracle(address(reverting));

        assertEq(address(wrapper.sanctionsOracle()), address(oracle));
    }

    // ─── deposit enforcement ─────────────────────────────────────────────

    function test_deposit_blocksSanctionedSender() public {
        oracle.setSanctioned(alice, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, alice));
        wrapper.deposit(AMOUNT);
    }

    function test_deposit_cleanPath() public {
        vm.prank(alice);
        assertTrue(wrapper.deposit(AMOUNT));
        assertEq(wrapper.balanceOf(alice), AMOUNT);
        assertEq(underlying.balanceOf(address(wrapper)), AMOUNT);
    }

    // ─── withdraw enforcement ────────────────────────────────────────────

    function test_withdraw_blocksSanctionedSender() public {
        vm.prank(alice);
        wrapper.deposit(AMOUNT);

        oracle.setSanctioned(alice, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, alice));
        wrapper.withdraw(AMOUNT);
    }

    function test_withdraw_cleanPath() public {
        vm.prank(alice);
        wrapper.deposit(AMOUNT);

        vm.prank(alice);
        assertTrue(wrapper.withdraw(AMOUNT));
        assertEq(wrapper.balanceOf(alice), 0);
        assertEq(underlying.balanceOf(alice), AMOUNT);
    }

    // ─── mint / _recover enforcement ──────────────────────────────────────

    function test_mint_blocksSanctionedRecipient() public {
        // Create a surplus of underlying inside the wrapper for _recover to sweep.
        underlying.mint(address(wrapper), AMOUNT);
        oracle.setSanctioned(carol, true);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, carol));
        wrapper.mint(carol);
    }

    function test_mint_cleanPath() public {
        underlying.mint(address(wrapper), AMOUNT);
        vm.prank(minter);
        wrapper.mint(carol);
        assertEq(wrapper.balanceOf(carol), AMOUNT);
    }

    // ─── transfer / transferFrom enforcement ──────────────────────────────

    function test_transfer_blocksSanctionedParty() public {
        vm.prank(alice);
        wrapper.deposit(AMOUNT);

        oracle.setSanctioned(bob, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, bob));
        wrapper.transfer(bob, 1e18);
    }

    function test_transfer_cleanPath() public {
        vm.prank(alice);
        wrapper.deposit(AMOUNT);

        vm.prank(alice);
        assertTrue(wrapper.transfer(bob, 1e18));
        assertEq(wrapper.balanceOf(bob), 1e18);
    }

    function test_transferFrom_blocksSanctionedFrom() public {
        vm.prank(alice);
        wrapper.deposit(AMOUNT);
        vm.prank(alice);
        wrapper.approve(carol, AMOUNT);

        oracle.setSanctioned(alice, true);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.AddressSanctioned.selector, alice));
        wrapper.transferFrom(alice, bob, 1e18);
    }

    // ─── fail-close on oracle revert ─────────────────────────────────────

    function test_deposit_failsClosedOnOracleRevert() public {
        oracle.setShouldRevert(true);
        vm.prank(alice);
        vm.expectRevert();
        wrapper.deposit(AMOUNT);
    }
}
