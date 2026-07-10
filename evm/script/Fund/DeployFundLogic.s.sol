// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {CoboFundOracle} from "../../src/Fund/CoboFundOracle.sol";
import {CoboFundToken} from "../../src/Fund/CoboFundToken.sol";
import {CoboFundVault} from "../../src/Fund/CoboFundVault.sol";

interface IFactory {
    function deploy(uint8 typ, bytes32 salt, bytes memory initCode) external returns (address);

    function getAddress(
        uint8 typ,
        bytes32 salt,
        address sender,
        bytes calldata initCode
    ) external view returns (address);
}

library FactoryLib {
    function doDeploy(IFactory factory, uint256 salt, bytes memory code) internal returns (address) {
        return factory.deploy(6, bytes32(salt), code); // Create2WithSenderAndEmit
    }
}

/// @title DeployFundLogic - Deploy all 3 Nav logic (implementation) contracts via CREATE2.
/// @dev Run: forge script script/DeployFundLogic.s.sol --rpc-url $RPC_URL --broadcast
contract DeployFundLogic is Script {
    using FactoryLib for IFactory;

    address public constant FACTORY = 0xC0B000003148E9c3E0D314f3dB327Ef03ADF8Ba7;

    function run() public {
        vm.startBroadcast();
        IFactory factory = IFactory(FACTORY);

        address oracleLogic = factory.doDeploy(
            uint256(bytes32("CoboFundOracleLogic")),
            type(CoboFundOracle).creationCode
        );
        console.log("CoboFundOracle logic:", oracleLogic);

        address nav4626Logic = factory.doDeploy(
            uint256(bytes32("CoboFundTokenLogic")),
            type(CoboFundToken).creationCode
        );
        console.log("CoboFundToken logic:", nav4626Logic);

        address vaultLogic = factory.doDeploy(uint256(bytes32("CoboFundVaultLogic")), type(CoboFundVault).creationCode);
        console.log("CoboFundVault logic:", vaultLogic);

        vm.stopBroadcast();
    }
}
