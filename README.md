# PaymentVerifierOZ — EIP-712 Payment Voucher PoC

A proof-of-concept for **off-chain signed payment vouchers** verified on-chain, built with
[Foundry](https://book.getfoundry.sh/) and OpenZeppelin's `EIP712` / `ECDSA` libraries.

An **authorizer** signs a `Payment` struct off-chain (EIP-712 typed data). Anyone can then
present that signature to the contract, which recovers the signer, checks it matches the
trusted authorizer, enforces a deadline, and consumes the nonce to prevent replay.

```
authorizer ──signs Payment voucher──▶ off-chain signature (v, r, s)
                                              │
                                              ▼
                          PaymentVerifierOZ.execute(payment, v, r, s)
                          ├─ deadline not passed?
                          ├─ nonce unused?
                          ├─ recovered signer == authorizer?
                          └─ mark nonce used + emit PaymentExecuted
```

## Layout

| Path | Description |
| --- | --- |
| `src/PaymentVerifierOZ.sol` | The voucher-verifying contract |
| `script/DeployPaymentVerifierOZ.s.sol` | Chain-agnostic deploy script |
| `offchain/signAndVerify.js` | Node/ethers harness that signs a voucher and verifies it against a deployed contract |
| `.env.example` | Env template for Foundry (deploy) |
| `offchain/.env.example` | Env template for the off-chain harness |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `anvil`, `cast`)
- [Node.js](https://nodejs.org/) 20+ (for `--env-file` support)

## Setup

Clone with submodules (forge-std + openzeppelin-contracts):

```shell
git clone --recurse-submodules <repo-url>
cd erc-712-poc

# If you already cloned without submodules:
git submodule update --init --recursive
```

Build the contracts:

```shell
forge build
```

Run the tests:

```shell
forge test
```

## The contract

`PaymentVerifierOZ` is constructed with a single `authorizer` address and uses the EIP-712
domain `EIP712("SohoPay", "1")`. Key methods:

- `digest(Payment)` — the full EIP-712 digest for a voucher (view).
- `recoverSigner(Payment, v, r, s)` — recovers the signing address (view).
- `verify(Payment, v, r, s)` — `true` if the signer is the trusted authorizer (view).
- `execute(Payment, v, r, s)` — validates deadline + nonce + signature, then consumes the nonce and emits `PaymentExecuted`.

The signed `Payment` struct:

```solidity
struct Payment {
    address to;       // recipient
    uint256 amount;   // amount in wei
    uint256 nonce;    // anti-replay
    uint256 deadline; // unix timestamp after which the voucher is invalid
}
```

## Deploying

Copy the env template and fill it in:

```shell
cp .env.example .env
```

| Var | Required | Notes |
| --- | --- | --- |
| `PRIVATE_KEY` | yes | Deployer key (hex, with or without `0x`) |
| `AUTHORIZER` | no | Address whose vouchers the contract trusts; defaults to the deployer |
| `SEPOLIA_RPC_URL` | for Sepolia | RPC endpoint, referenced by `foundry.toml` |
| `MAINNET_RPC_URL` | for mainnet | RPC endpoint, referenced by `foundry.toml` |
| `ETHERSCAN_API_KEY` | for `--verify` | Used by `forge script --verify` |

The deploy target is selected by `--rpc-url <name>`, where the named endpoints
(`local`, `sepolia`, `mainnet`) are defined in `foundry.toml`.

```shell
# Load env vars for the deploy
source .env

# Local Anvil (run `anvil` in another terminal first)
forge script script/DeployPaymentVerifierOZ.s.sol:DeployPaymentVerifierOZ \
  --rpc-url local --broadcast

# Sepolia (with source verification)
forge script script/DeployPaymentVerifierOZ.s.sol:DeployPaymentVerifierOZ \
  --rpc-url sepolia --broadcast --verify

# Ethereum mainnet
forge script script/DeployPaymentVerifierOZ.s.sol:DeployPaymentVerifierOZ \
  --rpc-url mainnet --broadcast --verify
```

Note the deployed address printed at the end — you'll need it for the off-chain harness.

## Off-chain signing + verification

The `offchain/` harness signs a `Payment` voucher with the authorizer key, verifies it
against a deployed contract, then broadcasts `execute()` to consume the nonce.

### Quick start (local Anvil)

1. In one terminal, start a local node:

   ```shell
   anvil
   ```

2. Deploy the contract (see above) with `--rpc-url local`. By default the authorizer is the
   deployer (Anvil account #0).

3. Set up the harness:

   ```shell
   cd offchain
   npm install
   cp .env.example .env
   ```

4. Set `CONTRACT` in `offchain/.env` to the deployed address, then run:

   ```shell
   npm run sign-verify
   ```

The script reads the ABI from Foundry's build artifact
(`out/PaymentVerifierOZ.sol/PaymentVerifierOZ.json`), so make sure you've run `forge build` first.

### Harness env vars (`offchain/.env`)

| Var | Required | Default |
| --- | --- | --- |
| `CONTRACT` | yes | — (deployed `PaymentVerifierOZ` address) |
| `AUTHORIZER_KEY` | yes | — must match the contract's `authorizer()` |
| `RPC_URL` | no | `http://127.0.0.1:8545` |
| `RECIPIENT` | no | Anvil account #1 |
| `AMOUNT` | no | `1 ether` (in wei) |
| `NONCE` | no | `1` |
| `DEADLINE` | no | now + 1 hour |

> The signing key (`AUTHORIZER_KEY`) **must** correspond to the address passed as the
> contract's `authorizer` at deploy time, or `verify()` returns `false`.

### Verifying against a testnet/mainnet deployment

Point the harness at the network and use the matching authorizer key in `offchain/.env`:

```shell
RPC_URL=https://your-rpc-endpoint
CONTRACT=0xYourDeployedAddress
AUTHORIZER_KEY=0xYourAuthorizerKey
```

Then `npm run sign-verify`. Note this broadcasts a real transaction that spends gas and
consumes the nonce on-chain.

## Foundry reference

```shell
forge build          # compile
forge test           # run tests
forge fmt            # format
forge snapshot       # gas snapshots
anvil                # local node
cast <subcommand>    # interact with contracts / chain
```

Docs: https://book.getfoundry.sh/
