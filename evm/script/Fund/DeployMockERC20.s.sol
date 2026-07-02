// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {MockERC20} from "../../test/Fund/mocks/MockERC20.sol";

/// @title DeployMockERC20 - Deploy MockERC20 token for testing
/// @dev Run: forge script script/DeployMockERC20.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
/// @dev Environment variables:
///      MOCK_TOKEN_NAME     - Token name (default: "Mock Asset Token")
///      MOCK_TOKEN_SYMBOL   - Token symbol (default: "MOCK")
///      MOCK_TOKEN_DECIMALS - Token decimals (default: 6)
contract DeployMockERC20 is Script {
    function run() public {
        // Read from environment or use defaults
        string memory name = vm.envOr("MOCK_TOKEN_NAME", string("Mock Asset Token"));
        string memory symbol = vm.envOr("MOCK_TOKEN_SYMBOL", string("MOCK"));
        uint8 decimals = uint8(vm.envOr("MOCK_TOKEN_DECIMALS", uint256(6)));

        vm.startBroadcast();

        // Deploy mock asset token
        MockERC20 asset = new MockERC20(name, symbol, decimals);
        console.log("Mock Asset deployed at:", address(asset));
        console.log("  Name:", name);
        console.log("  Symbol:", symbol);
        console.log("  Decimals:", decimals);

        vm.stopBroadcast();
    }
}
