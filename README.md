# ScorpionMICA2: MiCA-Compliant Upgradeable Stablecoin with Chainlink Proof-of-Reserve

![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.22-363636?logo=solidity)
![Foundry](https://img.shields.io/badge/Framework-Foundry-FFDB1C)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-UUPS%20Upgradeable-4E5EE4)
![Chainlink](https://img.shields.io/badge/Oracle-Chainlink%20Data%20Feeds-375BD2)
![Network](https://img.shields.io/badge/Testnet-Ethereum%20Sepolia-627EEA)

## Overview
**ScorpionMICA2 (`SCORPMICA2`)** is an institutional-grade, upgradeable ERC-20 stablecoin prototype engineered to demonstrate **Compliance-by-Design** under the European Union's **Markets in Crypto-Assets Regulation (MiCAR)** framework. 

Built with **Foundry** and deployed on the **Ethereum Sepolia Testnet** via an OpenZeppelin **UUPS (ERC-1967) Proxy**, the smart contract enforces algorithmic **Proof-of-Reserve (PoR)** checks prior to token issuance and embeds granular Role-Based Access Control (RBAC) for regulatory supervision, AML enforcement, and emergency circuit breaking.

---

## Key Architectural Pillars

### 1. Algorithmic Proof-of-Reserve (Chainlink Oracle Integration)
To prevent unbacked token issuance—a core prudential requirement under MiCAR for Asset-Referenced Tokens (ARTs) and E-Money Tokens (EMTs)—the `mint()` function is gated by real-time on-chain collateral verification:
- **Live Price Discovery:** Integrates Chainlink's `AggregatorV3Interface` (`ETH/USD` Price Feed on Sepolia: `0x694AA1769357215DE4FAC081bf1f309aDC325306`) via `getLatestPrice()`.
- **Decimal Alignment & Valuation:** Normalizes 18-decimal ETH balances held by the contract with 8-decimal Chainlink USD price feeds in `getReserveValue()` to compute real-time reserve valuation in 18-decimal USD terms.
- **Solvency Gatekeeper:** Enforces `currentReserveValue >= (totalSupply() + amount) * minCollateralRatio / 100` (defaulting to a 100% 1:1 reserve floor, configurable upward for over-collateralization) and checks against a hard `maxSupply` cap before executing `_mint()`.

### 2. MiCA Regulatory & AML Compliance Hooks
Drawing on institutional banking supervision standards, the contract implements multi-layered governance via OpenZeppelin's `AccessControlUpgradeable`:
- **`COMPLIANCE_ROLE` (AML Blacklisting & Asset Confiscation):** Overrides the internal `_update()` hook to block both incoming and outgoing transfers involving sanctioned or blacklisted addresses (`isBlacklisted`). Includes `wipeBlacklistedFunds()` to atomically burn illicitly held balances upon regulatory or judicial order.
- **`PAUSER_ROLE` (Emergency Circuit Breaker):** Inherits `ERC20PausableUpgradeable` to allow compliance officers to halt all secondary market transfers during oracle anomalies or regulatory inquiries.
- **`DEFAULT_ADMIN_ROLE` (Prudential Governance):** Dynamically manages `setMaxSupply()` (ensuring the new cap never falls below circulating supply) and `setMinCollateralRatio()` (strictly enforcing `>= 100%`).
- **`UPGRADER_ROLE` (Future-Proofing):** Utilizes the UUPS proxy pattern (`UUPSUpgradeable`) with `_disableInitializers()` in the constructor to allow seamless logic upgrades as EU regulatory technical standards (RTS) evolve.

---

## Repository Structure (Foundry Standard)

```text
scorpion-mica-stablecoin/
├── src/
│   └── ScorpionMICA2.sol          # Core UUPS upgradeable ERC-20 contract with Chainlink PoR & MiCA hooks
├── test/
│   └── ScorpionMICA2.t.sol        # Foundry unit test suite (Proxy initialization, PoR revert checks, Cap governance)
├── script/
│   └── DeployScorpion.s.sol       # Automated deployment script for Implementation + ERC1967Proxy on Sepolia
├── foundry.toml                   # Foundry compiler & OpenZeppelin remapping configuration
└── .env.example                   # Environment variable template for RPC & private key configuration
