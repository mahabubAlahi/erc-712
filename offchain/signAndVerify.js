// Off-chain EIP-712 signing + on-chain verification for PaymentVerifierOZ.
// See README.md for usage and env vars.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  JsonRpcProvider,
  Wallet,
  Contract,
  Signature,
  parseEther,
} from "ethers";

const __dirname = dirname(fileURLToPath(import.meta.url));

const RPC_URL = process.env.RPC_URL || "http://127.0.0.1:8545";
const CONTRACT = process.env.CONTRACT;
const AUTHORIZER_KEY = process.env.AUTHORIZER_KEY;
const RECIPIENT =
  process.env.RECIPIENT || "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
const AMOUNT = process.env.AMOUNT ? BigInt(process.env.AMOUNT) : parseEther("1");
const NONCE = process.env.NONCE ? BigInt(process.env.NONCE) : 1n;
const DEADLINE = process.env.DEADLINE
  ? BigInt(process.env.DEADLINE)
  : BigInt(Math.floor(Date.now() / 1000) + 3600);

if (!CONTRACT) {
  console.error("CONTRACT env var is required (deployed PaymentVerifierOZ address).");
  process.exit(1);
}
if (!AUTHORIZER_KEY) {
  console.error("AUTHORIZER_KEY env var is required (key that signs the voucher).");
  process.exit(1);
}

const artifactPath = join(
  __dirname,
  "..",
  "out",
  "PaymentVerifierOZ.sol",
  "PaymentVerifierOZ.json",
);
const { abi } = JSON.parse(readFileSync(artifactPath, "utf8"));

const provider = new JsonRpcProvider(RPC_URL);
const signer = new Wallet(AUTHORIZER_KEY, provider);
const contract = new Contract(CONTRACT, abi, provider);

const { chainId } = await provider.getNetwork();

// Must match the contract's constructor: EIP712("SohoPay", "1").
const domain = {
  name: "SohoPay",
  version: "1",
  chainId,
  verifyingContract: CONTRACT,
};

const types = {
  Payment: [
    { name: "to", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
};

const payment = {
  to: RECIPIENT,
  amount: AMOUNT,
  nonce: NONCE,
  deadline: DEADLINE,
};

console.log("Network chainId:", chainId.toString());
console.log("Contract:       ", CONTRACT);
console.log("Signer:         ", signer.address);
console.log("Payment:        ", {
  to: payment.to,
  amount: payment.amount.toString(),
  nonce: payment.nonce.toString(),
  deadline: payment.deadline.toString(),
});

// Sign off-chain.
const sig = await signer.signTypedData(domain, types, payment);
const { v, r, s } = Signature.from(sig);
console.log("\nSignature:", sig);
console.log("Split:    ", { v, r, s });

const onchainDigest = await contract.digest(payment);
console.log("\nOn-chain digest: ", onchainDigest);

// Verify on-chain via view calls.
const recovered = await contract.recoverSigner(payment, v, r, s);
const authorizer = await contract.authorizer();
const ok = await contract.verify(payment, v, r, s);

console.log("\nRecovered signer:", recovered);
console.log("Authorizer:      ", authorizer);
console.log("verify() =>      ", ok);

if (!ok) {
  console.error("\n Verification FAILED — signer is not the trusted authorizer.");
  process.exit(1);
}
console.log("\n Signature verified against the deployed contract.");

// Consume the voucher.
console.log("\nBroadcasting execute()...");
const tx = await contract.connect(signer).execute(payment, v, r, s);
const receipt = await tx.wait();
console.log("execute() mined in block", receipt.blockNumber, "tx:", receipt.hash);

const used = await contract.usedNonce(payment.nonce);
console.log("usedNonce[", payment.nonce.toString(), "] =>", used);
