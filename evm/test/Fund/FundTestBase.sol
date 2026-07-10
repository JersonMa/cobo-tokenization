// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {CoboFundOracle} from "../../src/Fund/CoboFundOracle.sol";
import {CoboFundToken} from "../../src/Fund/CoboFundToken.sol";
import {CoboFundVault} from "../../src/Fund/CoboFundVault.sol";
import {LibFundErrors} from "../../src/Fund/libraries/LibFundErrors.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSanctionsOracle} from "./mocks/MockSanctionsOracle.sol";

/// @dev Base test contract with full deployment setup for all Fund contracts.
abstract contract FundTestBase is Test {
    // ─── Contracts ──────────────────────────────────────────────────────
    MockERC20 public asset;
    CoboFundOracle public oracle;
    CoboFundToken public fundToken;
    CoboFundVault public vault;
    MockSanctionsOracle public sanctionsOracle;

    // Logic implementations (for upgrade tests)
    CoboFundOracle public oracleImpl;
    CoboFundToken public fundTokenImpl;
    CoboFundVault public vaultImpl;

    // ─── Addresses ──────────────────────────────────────────────────────
    address public admin = makeAddr("admin");
    address public navUpdater = makeAddr("navUpdater");
    address public manager = makeAddr("manager");
    address public blocklistAdmin = makeAddr("manager"); // Same as manager (BLOCKLIST_ADMIN_ROLE removed)
    address public redemptionApprover = makeAddr("redemptionApprover");
    address public emergencyGuardian = makeAddr("emergencyGuardian");
    address public settlementOperator = makeAddr("settlementOperator");
    address public upgrader = makeAddr("upgrader");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public attacker = makeAddr("attacker");

    // ─── Default Parameters ─────────────────────────────────────────────
    uint256 public constant INITIAL_NAV = 1e18; // 1:1
    uint256 public constant DEFAULT_APR = 5e16; // 5%
    uint256 public constant MAX_APR = 1e17; // 10%
    uint256 public constant MAX_APR_DELTA = 5e16; // 5%
    uint256 public constant MIN_UPDATE_INTERVAL = 1 days;
    uint256 public constant MIN_DEPOSIT_AMOUNT = 1e6; // 1 unit of asset token
    uint256 public constant MIN_REDEEM_SHARES = 1e18; // 1 share token
    uint8 public constant ASSET_DECIMALS = 6;
    uint8 public constant SHARE_DECIMALS = 18;

    // ─── Roles ──────────────────────────────────────────────────────────
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant NAV_UPDATER_ROLE = keccak256("NAV_UPDATER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REDEMPTION_APPROVER_ROLE = keccak256("REDEMPTION_APPROVER_ROLE");
    bytes32 public constant EMERGENCY_GUARDIAN_ROLE = keccak256("EMERGENCY_GUARDIAN_ROLE");
    bytes32 public constant SETTLEMENT_OPERATOR_ROLE = keccak256("SETTLEMENT_OPERATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function setUp() public virtual {
        // Deploy mock asset token
        asset = new MockERC20("Mock Asset Token", "ASSET", ASSET_DECIMALS);

        // Deploy sanctions oracle mock (no addresses sanctioned by default)
        sanctionsOracle = new MockSanctionsOracle();

        // Deploy logic implementations
        oracleImpl = new CoboFundOracle();
        fundTokenImpl = new CoboFundToken();
        vaultImpl = new CoboFundVault();

        // Deploy Oracle proxy
        bytes memory oracleInit = abi.encodeCall(
            CoboFundOracle.initialize,
            (admin, INITIAL_NAV, DEFAULT_APR, MAX_APR, MAX_APR_DELTA, MIN_UPDATE_INTERVAL)
        );
        oracle = CoboFundOracle(address(new ERC1967Proxy(address(oracleImpl), oracleInit)));

        // Deploy Nav4626 proxy (need vault address — use create2-style prediction or deploy vault first)
        // Since vault needs fundToken address, we deploy fundToken first with a placeholder, then vault, then update.
        // Actually: deploy fundToken first, then vault (vault needs fundToken), then fundToken.setVault is not needed
        // because we pass vault to fundToken.initialize.

        // We need to know addresses ahead of time. Use a workaround:
        // Deploy fundToken with a temporary vault, deploy vault, then update vault in fundToken.
        // OR: predict addresses. Let's use the simpler approach: deploy in order.

        // Step 1: Deploy fundToken with vault=address(1) temporarily
        // Step 2: Deploy vault with fundToken address
        // Step 3: Admin updates fundToken.vault

        // Actually simpler: deploy fundToken proxy, then vault proxy, then admin calls fundToken.setVault.
        // But fundToken.initialize requires vault_ != address(0). So let's predict the vault address.

        // Predict vault proxy address: deployer is this test contract, nonce is current + 2
        // (one for fundToken proxy deploy, one for vault implementation is already deployed)
        // Actually nonce tracking is fragile. Let's just deploy vault first with fundToken=address(this) temporarily,
        // then deploy fundToken with the real vault, then admin updates vault's fundToken.

        // SIMPLEST: compute address deterministically
        uint64 nonce = vm.getNonce(address(this));
        // Next deployment is fundToken proxy (nonce)
        // After that: vault proxy (nonce+1)
        address predictedVault = vm.computeCreateAddress(address(this), nonce + 1);

        bytes memory fundTokenInit = abi.encodeCall(
            CoboFundToken.initialize,
            (
                "Example Fund Token",
                "SHARE",
                SHARE_DECIMALS,
                address(asset),
                address(oracle),
                predictedVault,
                admin,
                MIN_DEPOSIT_AMOUNT,
                MIN_REDEEM_SHARES
            )
        );
        fundToken = CoboFundToken(address(new ERC1967Proxy(address(fundTokenImpl), fundTokenInit)));

        // Deploy Vault proxy
        bytes memory vaultInit = abi.encodeCall(CoboFundVault.initialize, (address(asset), address(fundToken), admin));
        vault = CoboFundVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));

        // Verify prediction was correct
        assertEq(address(vault), predictedVault, "Vault address prediction mismatch");

        // ─── Grant roles ─────────────────────────────────
        vm.startPrank(admin);

        // Oracle roles
        oracle.grantRole(NAV_UPDATER_ROLE, navUpdater);
        oracle.grantRole(UPGRADER_ROLE, upgrader);

        // Nav4626 roles
        fundToken.grantRole(MANAGER_ROLE, manager);
        fundToken.grantRole(REDEMPTION_APPROVER_ROLE, redemptionApprover);
        fundToken.grantRole(EMERGENCY_GUARDIAN_ROLE, emergencyGuardian);
        fundToken.grantRole(UPGRADER_ROLE, upgrader);

        // Vault roles
        vault.grantRole(SETTLEMENT_OPERATOR_ROLE, settlementOperator);
        vault.grantRole(UPGRADER_ROLE, upgrader);

        // Whitelist users in Nav4626
        fundToken.grantRole(MANAGER_ROLE, admin); // admin also as manager for setup convenience
        fundToken.addToWhitelist(user1);
        fundToken.addToWhitelist(user2);
        fundToken.addToWhitelist(user3);

        // Whitelist vault targets
        vault.setWhitelist(user1, true);
        vault.setWhitelist(user2, true);

        // Configure sanctions oracle on FundToken (Vault reads it from here)
        fundToken.setSanctionsOracle(address(sanctionsOracle));

        vm.stopPrank();

        // ─── Fund users ──────────────────────────────────
        asset.mint(user1, 1000e6); // 1000 units
        asset.mint(user2, 1000e6);
        asset.mint(user3, 1000e6);

        // Users approve FundToken to spend their asset tokens
        vm.prank(user1);
        asset.approve(address(fundToken), type(uint256).max);
        vm.prank(user2);
        asset.approve(address(fundToken), type(uint256).max);
        vm.prank(user3);
        asset.approve(address(fundToken), type(uint256).max);
    }

    // ─── Helper Functions ────────────────────────────────────────────────

    /// @dev Deposit assetAmount for a user and return shares minted.
    function _deposit(address user, uint256 assetAmount) internal returns (uint256 shares) {
        vm.prank(user);
        shares = fundToken.mint(assetAmount);
    }

    /// @dev Request redemption for a user and return reqId.
    function _requestRedemption(address user, uint256 shareAmount) internal returns (uint256 reqId) {
        vm.prank(user);
        reqId = fundToken.requestRedemption(shareAmount);
    }

    /// @dev Advance time and optionally update the oracle rate.
    function _advanceTimeAndUpdateRate(uint256 seconds_, uint256 newAPR) internal {
        vm.warp(block.timestamp + seconds_);
        vm.prank(navUpdater);
        oracle.updateRate(newAPR, "test");
    }
}
