// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title PaymentVerifierOZ
/// @notice Same payment-voucher PoC as `PaymentVerifier`, but built on OpenZeppelin's
///         EIP712 / ECDSA libraries and verifying split `(v, r, s)` signature parts.
/// @dev    `EIP712` supplies the cached domain separator (with EIP-5267 support) and
///         `_hashTypedDataV4`; `ECDSA.recover` handles the `\x19\x01` digest recovery
///         plus malleability/zero-address checks internally.
contract PaymentVerifierOZ is EIP712 {
    using ECDSA for bytes32;

    /// @notice The struct being signed off-chain.
    struct Payment {
        address to; // recipient of the payment
        uint256 amount; // amount in wei
        uint256 nonce; // per-message uniqueness (anti-replay)
        uint256 deadline; // unix timestamp after which the voucher is invalid
    }

    /// @dev keccak256("Payment(address to,uint256 amount,uint256 nonce,uint256 deadline)")
    bytes32 public constant PAYMENT_TYPEHASH =
        keccak256("Payment(address to,uint256 amount,uint256 nonce,uint256 deadline)");

    /// @notice The address whose signatures this contract trusts.
    address public immutable authorizer;

    /// @notice Tracks consumed nonces to prevent replay.
    mapping(uint256 => bool) public usedNonce;

    error InvalidSignature();
    error VoucherExpired();
    error NonceAlreadyUsed();

    event PaymentExecuted(address indexed to, uint256 amount, uint256 nonce);

    /// @dev Domain name/version must match what the off-chain signer uses.
    constructor(address _authorizer) EIP712("SohoPay", "1") {
        authorizer = _authorizer;
    }

    /// @notice Expose the domain separator (handy for off-chain tooling / debugging).
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Build the full EIP-712 digest for a voucher via OZ's `_hashTypedDataV4`.
    function digest(Payment calldata p) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(PAYMENT_TYPEHASH, p.to, p.amount, p.nonce, p.deadline));
        return _hashTypedDataV4(structHash);
    }

    /// @notice Recover the signer from split signature parts.
    function recoverSigner(Payment calldata p, uint8 v, bytes32 r, bytes32 s) public view returns (address) {
        return digest(p).recover(v, r, s);
    }

    /// @notice Verify a voucher was signed by the trusted authorizer (view-only).
    function verify(Payment calldata p, uint8 v, bytes32 r, bytes32 s) public view returns (bool) {
        return recoverSigner(p, v, r, s) == authorizer;
    }

    /// @notice Full happy-path: validate the voucher and consume it.
    function execute(Payment calldata p, uint8 v, bytes32 r, bytes32 s) external {
        if (block.timestamp > p.deadline) revert VoucherExpired();
        if (usedNonce[p.nonce]) revert NonceAlreadyUsed();
        if (recoverSigner(p, v, r, s) != authorizer) revert InvalidSignature();

        usedNonce[p.nonce] = true;
        emit PaymentExecuted(p.to, p.amount, p.nonce);
    }
}
