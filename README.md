# 🏦 DeFi Stablecoin (DSC)

A decentralized, exogenous, crypto-collateralized stablecoin system built with [Foundry](https://book.getfoundry.sh/). The system maintains a **1 DSC = 1 USD** peg through algorithmic minting/burning mechanics and overcollateralization with WETH and WBTC.

> This project is similar to **MakerDAO's DAI** — but with no governance, no fees, and backed only by WETH & WBTC.

## 📋 Table of Contents

- [About](#about)
- [How It Works](#how-it-works)
- [Smart Contracts](#smart-contracts)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Testing](#testing)
- [Deployment](#deployment)
- [Known Limitations](#known-limitations)

## About

**Decentralized Stable Coin (DSC)** is an algorithmic stablecoin system with the following properties:

| Property | Value |
|---|---|
| **Collateral Type** | Exogenous (WETH, WBTC) |
| **Stability Mechanism** | Algorithmic (minting & burning) |
| **Peg** | 1 DSC = 1 USD |
| **Collateralization** | 200% minimum (overcollateralized) |
| **Liquidation Threshold** | 50% |
| **Liquidation Bonus** | 10% |

## How It Works

### Depositing Collateral & Minting DSC

1. Users deposit **WETH** or **WBTC** as collateral into the `DSCEngine`.
2. The collateral value is determined using **Chainlink price feeds**.
3. Users can mint DSC up to **50% of their collateral value** (200% overcollateralization).

### Health Factor

The system tracks every user's **health factor**:

```
Health Factor = (Collateral Value in USD × Liquidation Threshold) / Total DSC Minted
```

- **Health Factor ≥ 1** → Position is healthy.
- **Health Factor < 1** → Position can be liquidated.

### Liquidation

If a user's health factor drops below 1 (e.g., collateral price drops), **anyone** can liquidate them:

1. The liquidator pays off the user's DSC debt.
2. The liquidator receives the user's collateral **+ a 10% bonus**.
3. This incentivizes users to keep the protocol solvent.

### Oracle Safety

The system uses an `OracleLib` library that checks for **stale Chainlink price data**. If a price feed hasn't been updated within **3 hours**, all operations revert — freezing the protocol by design to prevent incorrect liquidations.

## Smart Contracts

### Core Contracts

| Contract | Description |
|---|---|
| [`DecentralizedStableCoin.sol`](src/DecentralizedStableCoin.sol) | ERC20 token (DSC) with controlled mint/burn, owned by DSCEngine |
| [`DSCEngine.sol`](src/DSCEngine.sol) | Core engine handling collateral, minting, burning, and liquidations |
| [`OracleLib.sol`](src/Library/OracleLib.sol) | Library for stale price feed detection on Chainlink oracles |

### Scripts

| Script | Description |
|---|---|
| [`DeployDSC.s.sol`](script/DeployDSC.s.sol) | Deployment script for DSC + DSCEngine |
| [`HelperConfig.s.sol`](script/HelperConfig.s.sol) | Network config for Sepolia and local Anvil |

### Test Contracts

| Test | Description |
|---|---|
| [`DSCEngineTest.t.sol`](test/Unit/DSCEngineTest.t.sol) | Unit tests for constructor, price feeds, and deposit logic |
| [`Invariants.t.sol`](test/Fuzz/Invariants.t.sol) | Invariant/fuzz tests ensuring protocol solvency |
| [`Handler.t.sol`](test/Fuzz/Handler.t.sol) | Handler-based fuzz testing with constrained inputs |

## Getting Started

### Prerequisites

- [Git](https://git-scm.com/)
- [Foundry](https://getfoundry.sh/)

### Installation

```bash
git clone https://github.com/Shimul-12/DeFi-Stablecoin.git
cd DeFi-Stablecoin
forge install
forge build
```

## Usage

### Deposit Collateral and Mint DSC

```solidity
// 1. Approve the DSCEngine to spend your WETH
IERC20(weth).approve(address(engine), amount);

// 2. Deposit collateral and mint DSC in one transaction
engine.depositCollateralAndMintDsc(weth, collateralAmount, dscToMint);
```

### Redeem Collateral and Burn DSC

```solidity
// Burn DSC and redeem collateral in one transaction
engine.redeemCollateralForDsc(weth, collateralAmount, dscToBurn);
```

### Liquidate an Undercollateralized User

```solidity
// Liquidate a user by covering their debt — receive their collateral + 10% bonus
engine.liquidate(weth, userAddress, debtToCover);
```

## Testing

### Run All Tests

```bash
forge test
```

### Run Unit Tests

```bash
forge test --match-path test/Unit/*
```

### Run Invariant / Fuzz Tests

```bash
forge test --match-path test/Fuzz/Invariants.t.sol -vv
```

The invariant test suite verifies a critical property:

> **The total USD value of all collateral in the protocol must always be greater than or equal to the total supply of DSC.**

The fuzz test handler constrains random inputs to ensure meaningful test coverage:

- **Deposit Collateral** — Mints mock tokens, approves the engine, and deposits with bounded amounts.
- **Mint DSC** — Only mints for users who have deposited collateral, respecting the 200% overcollateralization ratio.
- **Redeem Collateral** — Only redeems up to the user's deposited balance.

### Invariant Test Configuration

Configured in `foundry.toml`:

```toml
[invariant]
runs = 1000
depth = 128
fail_on_revert = true
```

### Test Coverage

```bash
forge coverage
```

## Deployment

### Deploy to Local Anvil

```bash
# Start Anvil
anvil

# Deploy
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Deploy to Sepolia Testnet

```bash
forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

> **Note:** Set `PRIVATE_KEY` in your `.env` file before deploying to Sepolia.

## Known Limitations

1. **100% Collateralization Edge Case** — If the protocol becomes only 100% collateralized (instead of 200%), liquidations won't incentivize liquidators, and the protocol could become insolvent.
2. **Oracle Dependency** — If Chainlink price feeds go down or become stale (>3 hours), the protocol freezes entirely. Users cannot deposit, redeem, mint, or liquidate.
3. **Limited Collateral Types** — Only WETH and WBTC are supported as collateral.

---

## 🛠 Built With

- [Solidity](https://docs.soliditylang.org/) — Smart contract language
- [Foundry](https://book.getfoundry.sh/) — Development framework
- [OpenZeppelin](https://www.openzeppelin.com/contracts) — ERC20, ReentrancyGuard, Ownable
- [Chainlink](https://chain.link/) — Price feed oracles

## ✍️ Author

**Shimul Sharma**

## 📄 License

This project is licensed under the MIT License.