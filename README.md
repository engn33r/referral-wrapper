## Yearn Referral Deposit Wrapper

This repo is designed specifically for [Yearn partners](https://partners.yearn.fi/). It contains a minimal wrapper that forwards deposits into Yearn V3 vaults while emitting referral events (`ReferralDeposit`). The wrapper never owns shares or assets: users receive Yearn vault shares directly and can withdraw from the vault without interacting with this contract.

The goal is to keep this code as simple, secure, and gas efficient as possible. It only serves as a way to identify referred deposits to enable fee sharing with partners, because Yearn v3 vaults do not have a native referral system built-in.

Key properties:
- Single wrapper per chain: one deployment can be shared by all partners on a chain, with different referral values.
- Vault-safe: deposits are restricted to Yearn-endorsed V3 vaults via the on-chain registry.
- Immutable: the code is fixed at deployment; upgrades are performed by deploying a new wrapper and updating partner UIs.

## Usage

### Build

```shell
forge build
```

### Test (unit)

```shell
forge test
```

### Test (fork)

Fork tests require RPC URLs for the target networks. If not RPC URLs are given, the fork test logic is skipped.

```shell
MAINNET_RPC_URL=https://mainnet.gateway.tenderly.co BASE_RPC_URL=https://base.gateway.tenderly.co forge test --match-path test/YearnReferralDepositWrapper.fork.t.sol
```

To run a single fork test:

```shell
MAINNET_RPC_URL=... forge test --match-test testForkMainnetDeposit
BASE_RPC_URL=... forge test --match-test testForkBaseDeposit
```

### Coverage

The wrapper contract has 100% test coverage

```shell
forge coverage
```

### Deploy

```shell
forge script script/DeployYearnReferralDepositWrapper.s.sol:DeployYearnReferralDepositWrapper --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

#### How deployment works across chains

Deployments are performed via CreateX using CREATE2. The script targets the canonical CreateX address:
- `CREATE_X = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`

Because CREATE2 addresses are derived from `(deployer, salt, initCode)`, using the same `DEPLOY_SALT` and bytecode on every chain produces the same wrapper address on each chain (as long as CreateX is deployed at the same address on those chains). The deployment script reads:
- `DEPLOY_SALT` from the environment (defaults to a Yearn-related address cast to `bytes32`).
- `initCode` from `YearnReferralDepositWrapper`'s creation code.

To deploy on a new chain, point `--rpc-url` at that network and reuse the same `DEPLOY_SALT` to keep the address consistent.

#### How one contract supports all partner referrals

Users from partner sites call `depositWithReferral` with:
- `vault`: any Yearn-endorsed V3 vault on that chain.
- `receiver`: the end user receiving the shares.
- `referrer`: the partner's referral address (or other attribution address).

The wrapper emits the referral event containing both the `referrer` and the `vault`. This makes a single deployment usable by all partners and all Yearn-endorsed vaults on the chain, without storing partner state or whitelists in the contract.
