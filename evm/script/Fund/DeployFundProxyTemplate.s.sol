// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CoboFundOracle} from "../../src/Fund/CoboFundOracle.sol";
import {CoboFundToken} from "../../src/Fund/CoboFundToken.sol";
import {CoboFundVault} from "../../src/Fund/CoboFundVault.sol";

interface IFactory {
    function deploy(uint8 typ, bytes32 salt, bytes memory initCode) external returns (address);

    function deployAndInit(
        uint8 typ,
        bytes32 salt,
        bytes calldata initCode,
        bytes calldata callData
    ) external returns (address);

    function getAddress(
        uint8 typ,
        bytes32 salt,
        address sender,
        bytes calldata initCode
    ) external view returns (address);
}

/// @title DeployFundProxyTemplate - Parameterized deployment for multiple RWA funds.
/// @dev Template mode: can deploy multiple fund instances (one product per fund symbol).
///
///      Required environment variables:
///        ORACLE_LOGIC      - CoboFundOracle logic address
///        FUNDTOKEN_LOGIC   - CoboFundToken logic address
///        VAULT_LOGIC       - CoboFundVault logic address
///        ADMIN             - Admin address (receives DEFAULT_ADMIN_ROLE)
///        UNDERLYING_TOKEN  - Underlying asset address (any ERC20)
///
///        # Token configuration
///        TOKEN_NAME        - e.g., "SHARE Gold Fund"
///        TOKEN_SYMBOL      - e.g., "SHARE" (used in salt generation)
///        TOKEN_DECIMALS    - e.g., 18
///
///        # Oracle configuration
///        INITIAL_NAV       - e.g., 1000000000000000000 (1e18)
///        INITIAL_APR       - e.g., 0
///        MAX_APR           - e.g., 200000000000000000 (20%)
///        MAX_APR_DELTA     - e.g., 50000000000000000 (5%)
///        MIN_UPDATE_INTERVAL - e.g., 86400 (1 day)
///
///        # Token limits
///        MIN_DEPOSIT_AMOUNT - e.g., 1000000 (1 ASSET if decimals=6)
///        MIN_REDEEM_SHARES  - e.g., 1000000000000000000 (1 share if decimals=18)
///
///        # Optional: salt suffix for unique deployment
///        SALT_SUFFIX       - e.g., timestamp or counter (default: current timestamp)
contract DeployFundProxyTemplate is Script {
    address public constant FACTORY = 0xC0B000003148E9c3E0D314f3dB327Ef03ADF8Ba7;

    function run() public {
        // ─── Read logic addresses ───────────────────────────────────────
        address oracleLogic = vm.envAddress("ORACLE_LOGIC");
        address fundTokenLogic = vm.envAddress("FUNDTOKEN_LOGIC");
        address vaultLogic = vm.envAddress("VAULT_LOGIC");

        // ─── Read admin and asset ───────────────────────────────────────
        address adminAddr = vm.envAddress("ADMIN");
        address underlyingToken = vm.envAddress("UNDERLYING_TOKEN");

        // ─── Read token configuration ───────────────────────────────────
        string memory tokenName = vm.envString("TOKEN_NAME");
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        uint8 tokenDecimals = uint8(vm.envUint("TOKEN_DECIMALS"));

        // ─── Read oracle configuration ──────────────────────────────────
        uint256 initialNav = vm.envUint("INITIAL_NAV");
        uint256 initialAPR = vm.envUint("INITIAL_APR");
        uint256 maxAPR = vm.envUint("MAX_APR");
        uint256 maxAprDelta = vm.envUint("MAX_APR_DELTA");
        uint256 minUpdateInterval = vm.envUint("MIN_UPDATE_INTERVAL");

        // ─── Read token limits ──────────────────────────────────────────
        uint256 minDepositAmount = vm.envUint("MIN_DEPOSIT_AMOUNT");
        uint256 minRedeemShares = vm.envUint("MIN_REDEEM_SHARES");

        // ─── Generate unique salt ───────────────────────────────────────
        // Use symbol + optional suffix to avoid collision between different products
        string memory saltSuffix = vm.envOr("SALT_SUFFIX", vm.toString(block.timestamp));

        bytes32 oracleSalt = keccak256(abi.encodePacked(tokenSymbol, "_Oracle_", saltSuffix));
        bytes32 fundTokenSalt = keccak256(abi.encodePacked(tokenSymbol, "_FundToken_", saltSuffix));
        bytes32 vaultSalt = keccak256(abi.encodePacked(tokenSymbol, "_Vault_", saltSuffix));

        IFactory factory = IFactory(FACTORY);

        // ─── Prepare proxy init codes ───────────────────────────────────
        bytes memory oracleInitCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(oracleLogic, bytes(""))
        );
        bytes memory fundTokenInitCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(fundTokenLogic, bytes(""))
        );
        bytes memory vaultInitCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(vaultLogic, bytes(""))
        );

        vm.startBroadcast();

        // ─── 1. Deploy Oracle Proxy ─────────────────────────────────────
        bytes[] memory oracleData = new bytes[](1);
        oracleData[0] = abi.encodeCall(
            CoboFundOracle.initialize,
            (adminAddr, initialNav, initialAPR, maxAPR, maxAprDelta, minUpdateInterval)
        );
        bytes memory oracleCallData = abi.encodeWithSignature("multicall(bytes[])", oracleData);
        address oracleProxy = factory.deployAndInit(7, oracleSalt, oracleInitCode, oracleCallData);
        console.log("CoboFundOracle proxy:", oracleProxy);

        // ─── 2. Deploy FundToken Proxy ──────────────────────────────────
        // Predict vault address
        address predictedVault = factory.getAddress(7, vaultSalt, msg.sender, vaultInitCode);
        console.log("Predicted Vault address:", predictedVault);

        bytes[] memory fundTokenData = new bytes[](1);
        fundTokenData[0] = abi.encodeCall(
            CoboFundToken.initialize,
            (
                tokenName,
                tokenSymbol,
                tokenDecimals,
                underlyingToken,
                oracleProxy,
                predictedVault,
                adminAddr,
                minDepositAmount,
                minRedeemShares
            )
        );
        bytes memory fundTokenCallData = abi.encodeWithSignature("multicall(bytes[])", fundTokenData);
        address fundTokenProxy = factory.deployAndInit(7, fundTokenSalt, fundTokenInitCode, fundTokenCallData);
        console.log("CoboFundToken proxy:", fundTokenProxy);

        // ─── 3. Deploy Vault Proxy ──────────────────────────────────────
        bytes[] memory vaultData = new bytes[](1);
        vaultData[0] = abi.encodeCall(CoboFundVault.initialize, (underlyingToken, fundTokenProxy, adminAddr));
        bytes memory vaultCallData = abi.encodeWithSignature("multicall(bytes[])", vaultData);
        address vaultProxy = factory.deployAndInit(7, vaultSalt, vaultInitCode, vaultCallData);
        console.log("CoboFundVault proxy:", vaultProxy);

        // Verify predicted vault address matches
        require(vaultProxy == predictedVault, "Vault address prediction mismatch!");

        vm.stopBroadcast();

        // ─── Summary ────────────────────────────────────────────────────
        console.log("========================================");
        console.log("Deployment complete!");
        console.log("Product:", tokenSymbol);
        console.log("Oracle:", oracleProxy);
        console.log("FundToken:", fundTokenProxy);
        console.log("Vault:", vaultProxy);
        console.log("Admin:", adminAddr);
        console.log("========================================");
    }
}
