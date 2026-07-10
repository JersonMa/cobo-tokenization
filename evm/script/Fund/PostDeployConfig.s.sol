// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {CoboFundOracle} from "../../src/Fund/CoboFundOracle.sol";
import {CoboFundToken} from "../../src/Fund/CoboFundToken.sol";
import {CoboFundVault} from "../../src/Fund/CoboFundVault.sol";

/// @title PostDeployConfig - Post-deployment role and whitelist configuration for fund proxies.
/// @dev Run after DeployFundProxy.s.sol to configure all roles and whitelists per fund deployment checklist.
///
///      The broadcaster MUST be the DEFAULT_ADMIN_ROLE holder (the Safe multisig or admin EOA
///      that was passed as `admin` during deployment).
///
///      Required environment variables:
///        ORACLE_PROXY          - Deployed CoboFundOracle proxy address
///        FUNDTOKEN_PROXY         - Deployed CoboFundToken proxy address
///        VAULT_PROXY           - Deployed CoboFundVault proxy address
///
///        NAV_UPDATER           - Address authorized to call FundOracle.updateRate
///        MANAGER               - Address for FundToken MANAGER_ROLE (add/remove users from whitelist)
///        REDEMPTION_APPROVER   - Address for FundToken REDEMPTION_APPROVER_ROLE (approve/reject redemptions)
///        SETTLEMENT_OPERATOR   - Address for Vault SETTLEMENT_OPERATOR_ROLE (withdraw from vault)
///
///      Optional environment variables (set to address(0) or leave unset to skip):
///        EMERGENCY_GUARDIAN    - Address for FundToken EMERGENCY_GUARDIAN_ROLE (emergency pause)
///        UPGRADER              - Address for UPGRADER_ROLE on all 3 contracts
///        SETTLEMENT_TARGETS    - Comma-separated list of Vault settlement whitelist addresses
///        SANCTIONS_ORACLE      - Address of a contract implementing ISanctionsOracle. Leave unset
///                                to skip; admin can install later via setSanctionsOracle.
///
///      Run: forge script script/PostDeployConfig.s.sol --rpc-url $RPC_URL --broadcast
contract PostDeployConfig is Script {
    function run() public {
        // ─── Read deployed proxy addresses ──────────────────────────────
        address oracleProxy = vm.envAddress("ORACLE_PROXY");
        address fundTokenProxy = vm.envAddress("FUNDTOKEN_PROXY");
        address vaultProxy = vm.envAddress("VAULT_PROXY");

        // ─── Read role assignee addresses ───────────────────────────────
        address navUpdater = vm.envAddress("NAV_UPDATER");
        address manager = vm.envAddress("MANAGER");
        address redemptionApprover = vm.envAddress("REDEMPTION_APPROVER");
        address settlementOperator = vm.envAddress("SETTLEMENT_OPERATOR");

        // Optional: Emergency Guardian (address(0) to skip)
        address emergencyGuardian = vm.envOr("EMERGENCY_GUARDIAN", address(0));

        // Optional: Upgrader role for all 3 contracts (address(0) to skip)
        address upgrader = vm.envOr("UPGRADER", address(0));

        // Optional: Vault settlement target whitelist (comma-separated addresses)
        // Parse as a string then split; empty string means no targets.
        string memory settlementTargetsRaw = vm.envOr("SETTLEMENT_TARGETS", string(""));

        // Optional: Sanctions screening oracle (address(0) / unset to skip — operator
        // can later run setSanctionsOracle from the admin multisig).
        address sanctionsOracle = vm.envOr("SANCTIONS_ORACLE", address(0));

        // ─── Cast proxy addresses to contract interfaces ────────────────
        CoboFundOracle oracle = CoboFundOracle(oracleProxy);
        CoboFundToken fundToken = CoboFundToken(fundTokenProxy);
        CoboFundVault vault = CoboFundVault(vaultProxy);

        // ─── Log configuration summary ──────────────────────────────────
        console.log("========================================");
        console.log("PostDeployConfig - Role Configuration");
        console.log("========================================");
        console.log("Oracle proxy:", oracleProxy);
        console.log("FundToken proxy:", fundTokenProxy);
        console.log("Vault proxy:", vaultProxy);
        console.log("----------------------------------------");
        console.log("NAV Updater:", navUpdater);
        console.log("Manager:", manager);
        console.log("Redemption Approver:", redemptionApprover);
        console.log("Settlement Operator:", settlementOperator);
        console.log("Emergency Guardian:", emergencyGuardian);
        console.log("Upgrader:", upgrader);
        console.log("Sanctions Oracle:", sanctionsOracle);
        console.log("========================================");

        vm.startBroadcast();

        // ─── 1. FundOracle: Whitelist NAV updater ────────────────────────
        // Uses the convenience wrapper setWhitelist(address, bool) which
        // internally grants NAV_UPDATER_ROLE.
        console.log("[1/7] FundOracle: whitelisting NAV updater...");
        oracle.setWhitelist(navUpdater, true);

        // ─── 2. FundToken: Grant MANAGER_ROLE ─────────────────────────────
        // MANAGER_ROLE holders can manage whitelist (add/remove users).
        console.log("[2/6] FundToken: granting MANAGER_ROLE...");
        fundToken.grantRole(fundToken.MANAGER_ROLE(), manager);

        // ─── 3. FundToken: Grant REDEMPTION_APPROVER_ROLE ─────────────────
        // REDEMPTION_APPROVER_ROLE holders can approve/reject redemption requests.
        console.log("[3/6] FundToken: granting REDEMPTION_APPROVER_ROLE...");
        fundToken.grantRole(fundToken.REDEMPTION_APPROVER_ROLE(), redemptionApprover);

        // ─── 4. FundToken: Grant EMERGENCY_GUARDIAN_ROLE (optional) ───────
        // EMERGENCY_GUARDIAN_ROLE can trigger emergency pause. Skip if address(0).
        if (emergencyGuardian != address(0)) {
            console.log("[4/6] FundToken: granting EMERGENCY_GUARDIAN_ROLE...");
            fundToken.grantRole(fundToken.EMERGENCY_GUARDIAN_ROLE(), emergencyGuardian);
        } else {
            console.log("[4/6] FundToken: EMERGENCY_GUARDIAN_ROLE skipped (not configured)");
        }

        // ─── 5. Vault: Grant SETTLEMENT_OPERATOR_ROLE ───────────────────
        // SETTLEMENT_OPERATOR_ROLE holders can call Vault.withdraw to transfer
        // ASSET to whitelisted settlement target addresses.
        console.log("[5/6] Vault: granting SETTLEMENT_OPERATOR_ROLE...");
        vault.grantRole(vault.SETTLEMENT_OPERATOR_ROLE(), settlementOperator);

        // ─── 6. Vault: Whitelist settlement target addresses ────────────
        // These are the custody/project addresses that the settlement operator
        // can withdraw ASSET to.
        if (bytes(settlementTargetsRaw).length > 0) {
            console.log("[6/6] Vault: whitelisting settlement targets...");
            address[] memory targets = _parseAddressList(settlementTargetsRaw);
            for (uint256 i = 0; i < targets.length; i++) {
                console.log("  -> whitelisting:", targets[i]);
                vault.setWhitelist(targets[i], true);
            }
        } else {
            console.log("[6/6] Vault: settlement targets skipped (none configured)");
        }

        // ─── Optional: Grant UPGRADER_ROLE on all 3 contracts ───────────
        if (upgrader != address(0)) {
            console.log("[Opt] Granting UPGRADER_ROLE on all contracts...");
            oracle.grantRole(oracle.UPGRADER_ROLE(), upgrader);
            fundToken.grantRole(fundToken.UPGRADER_ROLE(), upgrader);
            vault.grantRole(vault.UPGRADER_ROLE(), upgrader);
        }

        // ─── Optional: Configure sanctions screening oracle ──────────────
        // FundToken.sanctionsOracle is the single source of truth; Vault reads it
        // when enforcing screening on withdraw.
        if (sanctionsOracle != address(0)) {
            console.log("[Opt] Configuring sanctions oracle on FundToken...");
            fundToken.setSanctionsOracle(sanctionsOracle);
        } else {
            console.log("[Opt] Sanctions oracle skipped (admin can install later via setSanctionsOracle)");
        }

        vm.stopBroadcast();

        // ─── Final summary ──────────────────────────────────────────────
        console.log("========================================");
        console.log("PostDeployConfig complete!");
        console.log("========================================");
    }

    // ─── Internal Helpers ───────────────────────────────────────────────

    /// @dev Parse a comma-separated string of hex addresses into an address array.
    ///      Example input: "0xAbc...123,0xDef...456"
    function _parseAddressList(string memory csv) internal pure returns (address[] memory) {
        bytes memory raw = bytes(csv);
        if (raw.length == 0) return new address[](0);

        // Count commas to determine array size
        uint256 count = 1;
        for (uint256 i = 0; i < raw.length; i++) {
            if (raw[i] == ",") count++;
        }

        address[] memory result = new address[](count);
        uint256 idx = 0;
        uint256 start = 0;

        for (uint256 i = 0; i <= raw.length; i++) {
            if (i == raw.length || raw[i] == ",") {
                // Extract substring [start, i)
                bytes memory segment = new bytes(i - start);
                for (uint256 j = start; j < i; j++) {
                    segment[j - start] = raw[j];
                }
                // Skip leading/trailing whitespace
                segment = _trimWhitespace(segment);
                result[idx] = _parseAddress(segment);
                idx++;
                start = i + 1;
            }
        }

        return result;
    }

    /// @dev Trim leading and trailing spaces from bytes.
    function _trimWhitespace(bytes memory input) internal pure returns (bytes memory) {
        uint256 start = 0;
        uint256 end = input.length;
        while (start < end && (input[start] == " " || input[start] == "\t")) start++;
        while (end > start && (input[end - 1] == " " || input[end - 1] == "\t")) end--;
        bytes memory trimmed = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            trimmed[i - start] = input[i];
        }
        return trimmed;
    }

    /// @dev Parse a hex address string (with 0x prefix) into an address.
    function _parseAddress(bytes memory addrStr) internal pure returns (address) {
        require(addrStr.length == 42, "PostDeployConfig: invalid address length");
        require(addrStr[0] == "0" && (addrStr[1] == "x" || addrStr[1] == "X"), "PostDeployConfig: missing 0x prefix");

        uint160 addr = 0;
        for (uint256 i = 2; i < 42; i++) {
            uint8 b = uint8(addrStr[i]);
            uint8 nibble;
            if (b >= 48 && b <= 57) {
                nibble = b - 48; // '0'-'9'
            } else if (b >= 65 && b <= 70) {
                nibble = b - 55; // 'A'-'F'
            } else if (b >= 97 && b <= 102) {
                nibble = b - 87; // 'a'-'f'
            } else {
                revert("PostDeployConfig: invalid hex character");
            }
            addr = addr * 16 + uint160(nibble);
        }
        return address(addr);
    }
}
