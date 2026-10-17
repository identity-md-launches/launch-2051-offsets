# Local security review

## Scope and design

Reviewed `src/Offsets.sol`, its five vendored OpenZeppelin Solidity files, and
the build configuration against the supplied security reference and protected
test definitions. The only custom token logic fixes the metadata and mints
`1,000,000,000 * 10**18` units to `msg.sender` in the constructor.

- **Supply:** The constructor is the sole reachable mint path. No external
  mint, burn, initialization, upgrade, or delegated execution path exists.
- **Authority:** `transfer` spends only the caller's balance. `approve` sets
  only the caller's allowance. `transferFrom` enforces the spender's allowance,
  including when the spender is the original deployer. There are no roles or
  privileged transfer exceptions.
- **Accounting:** The inherited implementation checks balances and allowances
  before subtraction. Its unchecked balance updates are bounded by the fixed
  supply. Self-transfers preserve balances. Reverting transfers also roll back
  any allowance update made earlier in the call.
- **External calls:** No token operation or constructor calls an external
  contract. There are no callbacks, oracles, randomness, signatures, external
  libraries, or reentrancy entry points requiring additional machinery.
- **Launch compatibility:** CREATE/CREATE2 deployment needs no arguments or
  outside contracts. The immediate factory receives the complete supply.
  Factory distribution, claims, and pool-facing transfers have no token fees
  or restrictions beyond ordinary ERC-20 balance and recipient checks.
- **Build:** Solidity and EVM settings are explicit, metadata hashing is
  disabled, dependencies are vendored, and no FFI or filesystem access is
  enabled. The deployed runtime is checked for size and forbidden opcodes.

The intentionally preserved ERC-20 behaviors include zero-value transfers,
self-transfers, replaceable approvals, and the maximum-uint allowance convention.
They are covered by tests; the general security checklist's advice about zero
amounts and unlimited approvals is not used to change the requested token.

## Validation and limits

Local validation uses `forge build`, `forge test` with the assignment's seed,
and `forge fmt --check`. Tests include negative cases with exact custom errors,
fuzzed amounts, and stateful conservation/balance/allowance invariants. No
Slither or Mythril analysis is claimed.

The local launch test checks distribution and claim amounts using a small test
factory. It does not emulate Uniswap v4 liquidity provisioning or swaps. The
supplied protected tests import the network's launch harness and require its
resolved manifest inputs; those dependencies and inputs are not included in
this assignment. Their full launch, swap, and application-owner checks remain
the independent verifier's responsibility. This deliverable has no application
contracts or owners to configure.

This is a local implementation review, not an independent security audit.
Independent adversarial review, launch admission, deployment, and explorer
verification remain the network's release steps. No live transaction has been
sent by this project.
