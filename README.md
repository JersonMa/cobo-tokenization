# Cobo Tokenization ERC20 

A sophisticated, upgradeable ERC20 token implementation with role-based access control, built using the Foundry framework and OpenZeppelin's upgradeable contracts.

## 🌟 Features

### Core Token Functionality
- **ERC20 Standard**: Full compliance with ERC20 token standard
- **Upgradeable**: UUPS (Universal Upgradeable Proxy Standard) implementation
- **Multicall Support**: Batch multiple function calls in a single transaction

### Contracts

| Network         | Contract Address                                                               |
|------------------|------------------------------------------------------------------------------|
| Sepolia Testnet  | [`0xA3d7b4Af8603B95A6fAaf0758Db4440871fC465c`](https://sepolia.etherscan.io/address/0xA3d7b4Af8603B95A6fAaf0758Db4440871fC465c#code) |
| Ethereum Mainnet | [`0xA3d7b4Af8603B95A6fAaf0758Db4440871fC465c`](https://etherscan.io/address/0xA3d7b4Af8603B95A6fAaf0758Db4440871fC465c#code) |
| Base Network     | [`0xA3d7b4Af8603B95A6fAaf0758Db4440871fC465c`](https://basescan.org/address/0xA3d7b4Af8603B95A6fAaf0758Db4440871fC465c#code) |
| BSC Network      | [`0xA3d7b4Af8603B95A6fAaf0758Db4440871fC465c`](https://bscscan.com/address/0xA3d7b4Af8603B95A6fAaf0758Db4440871fC465c#code) |
| Arbitrum One Network      | [`0xA3d7b4Af8603B95A6fAaf0758Db4440871fC465c`](https://arbiscan.io/address/0xA3d7b4Af8603B95A6fAaf0758Db4440871fC465c#code) |

# Cobo Tokenization ERC20 Wrapper 

### Contracts

| Network         | Contract Address                                                               |
|------------------|------------------------------------------------------------------------------|
| Sepolia Testnet  | [`0x162090E61445B8Ca6B7CbbFb494C77D167e2F32b`](https://sepolia.etherscan.io/address/0x162090E61445B8Ca6B7CbbFb494C77D167e2F32b#code) |
| Ethereum Mainnet | [`0x162090E61445B8Ca6B7CbbFb494C77D167e2F32b`](https://etherscan.io/address/0x162090E61445B8Ca6B7CbbFb494C77D167e2F32b#code) |
| Base Network     | [`0x162090E61445B8Ca6B7CbbFb494C77D167e2F32b`](https://basescan.org/address/0x162090E61445B8Ca6B7CbbFb494C77D167e2F32b#code) |
| BSC Network      | [`0x162090E61445B8Ca6B7CbbFb494C77D167e2F32b`](https://bscscan.com/address/0x162090E61445B8Ca6B7CbbFb494C77D167e2F32b#code) |
| Arbitrum One Network      | [`0x162090E61445B8Ca6B7CbbFb494C77D167e2F32b`](https://arbiscan.io/address/0x162090E61445B8Ca6B7CbbFb494C77D167e2F32b#code) |

# Cobo Fund Tokenization

A NAV-based fund tokenization system that wraps real-world assets (e.g., gold, bitcoin) into ERC20 share tokens with continuous NAV accrual.

## Features
- **NAV Oracle**: Continuous APR-based price accrual
- **Share Token**: ERC20-compliant fund shares with mint/redeem
- **Asset Vault**: Secure custody with settlement operations
- **Compliance**: Built-in whitelist, two-step redemption approval, and optional on-chain sanctions screening via pluggable `ISanctionsOracle`

### Logic Contracts

| Sepolia Testnet Contract         | Address                                                               |
|------------------|-----------------------------------------------------------------------|
| Oracle Logic     | [`0xc0601667705F8C96c2e2F452E494bd5CC3b262BA`](https://sepolia.etherscan.io/address/0xc0601667705F8C96c2e2F452E494bd5CC3b262BA) |
| FundToken Logic  | [`0xAc5021d88e8003D30CCE6b089A3982060907a917`](https://sepolia.etherscan.io/address/0xAc5021d88e8003D30CCE6b089A3982060907a917) |
| Vault Logic      | [`0x7D89fD39EE0d40b3024814B8874df710f1edeA00`](https://sepolia.etherscan.io/address/0x7D89fD39EE0d40b3024814B8874df710f1edeA00) |

| Ethereum Contract         | Address                                                               |
|------------------|-----------------------------------------------------------------------|
| Oracle Logic     | [`0xc0601667705F8C96c2e2F452E494bd5CC3b262BA`](https://etherscan.io/address/0xc0601667705F8C96c2e2F452E494bd5CC3b262BA) |
| FundToken Logic  | [`0xAc5021d88e8003D30CCE6b089A3982060907a917`](https://etherscan.io/address/0xAc5021d88e8003D30CCE6b089A3982060907a917) |
| Vault Logic      | [`0x7D89fD39EE0d40b3024814B8874df710f1edeA00`](https://etherscan.io/address/0x7D89fD39EE0d40b3024814B8874df710f1edeA00) |

| Base Network Contract         | Address                                                               |
|------------------|-----------------------------------------------------------------------|
| Oracle Logic     | [`0xc0601667705F8C96c2e2F452E494bd5CC3b262BA`](https://basescan.org/address/0xc0601667705F8C96c2e2F452E494bd5CC3b262BA) |
| FundToken Logic  | [`0xAc5021d88e8003D30CCE6b089A3982060907a917`](https://basescan.org/address/0xAc5021d88e8003D30CCE6b089A3982060907a917) |
| Vault Logic      | [`0x7D89fD39EE0d40b3024814B8874df710f1edeA00`](https://basescan.org/address/0x7D89fD39EE0d40b3024814B8874df710f1edeA00) |

| Arbitrum One Network Contract         | Address                                                               |
|------------------|-----------------------------------------------------------------------|
| Oracle Logic     | [`0xc0601667705F8C96c2e2F452E494bd5CC3b262BA`](https://arbiscan.io/address/0xc0601667705F8C96c2e2F452E494bd5CC3b262BA) |
| FundToken Logic  | [`0xAc5021d88e8003D30CCE6b089A3982060907a917`](https://arbiscan.io/address/0xAc5021d88e8003D30CCE6b089A3982060907a917) |
| Vault Logic      | [`0x7D89fD39EE0d40b3024814B8874df710f1edeA00`](https://arbiscan.io/address/0x7D89fD39EE0d40b3024814B8874df710f1edeA00) |

📚 **Documentation**: See [evm/src/Fund/README.md](./evm/src/Fund/README.md) for deployment and usage.

---

# Cobo Tokenization Solana

### Contracts

| Network         | Contract Address                                                               |
|------------------|------------------------------------------------------------------------------|
| Devnet  | [`2LbadSfQEGMooXUB3tmkXufVGKrQBkjR7UybxnvmwH4L`](https://solscan.io/account/2LbadSfQEGMooXUB3tmkXufVGKrQBkjR7UybxnvmwH4L?cluster=devnet) |
