# Offsets (OFFSETS)

A fixed-supply ERC-20 for the IdentityMD custom-token launch. The deployable
contract is `src/Offsets.sol:Offsets`. There are no application contracts.

| Parameter | Value |
| --- | --- |
| Name | `Offsets` |
| Symbol | `OFFSETS` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Intended launch chain | Ethereum, chain ID `1` |

The constructor mints the entire supply once. In a factory deployment the
factory receives every token; the transaction origin receives none automatically.
`INITIAL_SUPPLY` is the named constant for the supply in smallest units.

## Behavior and assumptions

The token uses the unmodified ERC-20 implementation from OpenZeppelin Contracts
v5.0.2. Ordinary transfers and approved `transferFrom` calls deliver the exact
amount, with no token tax, fee, burn, rebase, transfer limit, or recipient callback.
Zero-value transfers to valid recipients and self-transfers are supported.
Transfers to the zero address revert. Invalid transfers revert with ERC-20
custom errors instead of returning `false`; successful operations return `true`.

The deployer has no administrative powers. There is no owner, mint entry point,
burn entry point, pause, blocklist, seizure, proxy, upgrade, or initializer.
The supply and metadata cannot change. No oracle, registry, external service,
address configuration, or post-deployment initialization is required.

`approve` replaces an allowance; zero revokes it. Finite allowances decrease on
`transferFrom`; `type(uint256).max` is treated as unlimited and stays unchanged.
Approvals are specific to each holder/spender pair. Spending allowance does not
emit an additional `Approval` event in this vendored implementation; integrations
should read `allowance` when they need its current value.

## Build and test

Install Foundry and Solidity `0.8.26`. All Solidity dependencies and their licenses
are ordinary files in `lib/`; no dependency download, submodule, package install,
RPC, wallet, or environment value is needed for the build or tests. The compiler
must already be available for an offline build.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x2a53ba835e67847f40b4d4fbeca5cff867b2712c79797348b5f930758c66eee5 forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, the Cancun EVM target, optimization with
200 runs, and `bytecode_hash = "none"`. It enables neither FFI nor filesystem
permissions. Fuzz tests run 512 cases each; stateful invariants run 128 sequences
of up to 64 calls each. Tests use isolated local chains and do not read or mutate
environment variables. The command above supplies the verifier's seed to Forge.

The tests cover initial allocation and its mint event, CREATE and CREATE2 factory
deployment, exact distribution and claim transfers, transfer/approval events,
allowance exhaustion and revocation, unlimited approvals, self/zero transfers,
invalid recipients, insufficient funds/allowance, failure rollback, absent admin
functions, and forbidden runtime opcodes. Stateful tests compare balances and
allowances with an independent ledger and check conservation of the full supply.

Dependency versions, immutable upstream commits, and per-file SHA-256 hashes are
recorded in [docs/dependencies.json](docs/dependencies.json). The OpenZeppelin
subset contains all imports needed by the token; forge-std v1.9.7 is used only
by tests. Neither dependency is a submodule.

## Deployment and operational responsibilities

The network's deployer deploys `Offsets` directly from its compiled creation
bytecode with no constructor arguments and no ETH value. Use the exact pinned
compiler settings. No library linking is needed. Do not deploy it behind a proxy:
the supply is established by the constructor.

For the specified launch the factory receives the entire supply, then handles
the 10% swarm allocation, 80% pool allocation, and 10% remainder itself. These
allocations and the pool configuration are external to the token. The separate
manifest step is responsible for `launch.json` and the supplied economics;
this project supplies only the token. Test fixture addresses are local actors,
not deployment parameters.

After launch:

- The deployer verifies the contract source and bytecode, metadata, total supply,
  and constructor mint event, and checks the factory's subsequent distribution.
- No token administrator, keeper, setter, or ownership handover is required.
- Holders control their balances and allowances. Integrators should request only
  the allowance they need. To change an existing nonzero allowance, revoke it and
  wait for confirmation before granting a replacement; transaction ordering can
  otherwise allow spending under both the old and new approvals.
- Recipients must be able to use ERC-20 tokens. Sending tokens to this token's
  own address, or an incompatible contract, can lock them permanently. There is
  no rescue function, and no administrator can recover mistaken transfers or
  lost keys. The contract has no payable entry point or native-ETH withdrawal.

See [docs/security-review.md](docs/security-review.md) for the local review and
the boundary between these tests and the network's independent launch checks.
