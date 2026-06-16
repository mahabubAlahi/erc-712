// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {PaymentVerifierOZ} from "../src/PaymentVerifierOZ.sol";

/// @title DeployPaymentVerifierOZ
/// @notice Chain-agnostic deploy script for `PaymentVerifierOZ`.
///         Works against mainnet, Sepolia, a local Anvil node, or any EVM chain —
///         the target is selected entirely by the `--rpc-url` you pass on the CLI.
///
/// @dev Configuration is read from environment variables:
///        - PRIVATE_KEY : deployer key (hex, with or without 0x). Required.
///        - AUTHORIZER  : address whose vouchers the contract will trust.
///                        Optional; defaults to the deployer address if unset.
///
///      Usage:
///        # Local (Anvil)
///        forge script script/DeployPaymentVerifierOZ.s.sol:DeployPaymentVerifierOZ \
///          --rpc-url local --broadcast
///
///        # Sepolia (with verification)
///        forge script script/DeployPaymentVerifierOZ.s.sol:DeployPaymentVerifierOZ \
///          --rpc-url sepolia --broadcast --verify
///
///        # Ethereum mainnet
///        forge script script/DeployPaymentVerifierOZ.s.sol:DeployPaymentVerifierOZ \
///          --rpc-url mainnet --broadcast --verify
contract DeployPaymentVerifierOZ is Script {
    function run() external returns (PaymentVerifierOZ deployed) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Default the authorizer to the deployer if not explicitly provided.
        address authorizer = vm.envOr("AUTHORIZER", deployer);

        console2.log("Chain ID:   ", block.chainid);
        console2.log("Deployer:   ", deployer);
        console2.log("Authorizer: ", authorizer);

        vm.startBroadcast(deployerKey);
        deployed = new PaymentVerifierOZ(authorizer);
        vm.stopBroadcast();

        console2.log("PaymentVerifierOZ deployed at:", address(deployed));
    }
}
