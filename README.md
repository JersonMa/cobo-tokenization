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
| Sepolia Testnet  | [`0xa3d7b4af8603b95a6faaf0758db4440871fc465c`](https://sepolia.etherscan.io/address/0xa3d7b4af8603b95a6faaf0758db4440871fc465c#code) |
| Ethereum Mainnet | [`0x2da3BF4087703BFE4009F49E0B8d5602536F86a1`](https://etherscan.io/address/0x2da3BF4087703BFE4009F49E0B8d5602536F86a1#code) |
| Base Network     | [`0x2da3bf4087703bfe4009f49e0b8d5602536f86a1`](https://basescan.org/address/0x2da3BF4087703BFE4009F49E0B8d5602536F86a1#code) |
| BSC Network      | [`0x2da3BF4087703BFE4009F49E0B8d5602536F86a1`](https://bscscan.com/address/0x2da3BF4087703BFE4009F49E0B8d5602536F86a1#code) |
| Arbitrum One Network      | [`0x2da3BF4087703BFE4009F49E0B8d5602536F86a1`](https://arbiscan.io/address/0x2da3BF4087703BFE4009F49E0B8d5602536F86a1#code) |

# Cobo Tokenization ERC20 Wrapper 

### Contracts

| Network         | Contract Address                                                               |
|------------------|------------------------------------------------------------------------------|
| Sepolia Testnet  | [`0x162090e61445b8ca6b7cbbfb494c77d167e2f32b`](https://sepolia.etherscan.io/address/0x162090e61445b8ca6b7cbbfb494c77d167e2f32b#code) |
| Ethereum Mainnet | [`0xaeD271103F86DB5624e69977227e30c3C00D8AEB`](https://etherscan.io/address/0xaeD271103F86DB5624e69977227e30c3C00D8AEB#code) |
| Base Network     | [`0xaeD271103F86DB5624e69977227e30c3C00D8AEB`](https://basescan.org/address/0xaeD271103F86DB5624e69977227e30c3C00D8AEB#code) |
| BSC Network      | [`0xaeD271103F86DB5624e69977227e30c3C00D8AEB`](https://bscscan.com/address/0xaeD271103F86DB5624e69977227e30c3C00D8AEB#code) |
| Arbitrum One Network      | [`0xaeD271103F86DB5624e69977227e30c3C00D8AEB`](https://arbiscan.io/address/0xaeD271103F86DB5624e69977227e30c3C00D8AEB#code) |

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
| Oracle Logic     | [`0x0CEc310611866849fe07759f3635EB8D39BbA8ea`](https://sepolia.etherscan.io/address/0x0CEc310611866849fe07759f3635EB8D39BbA8ea) |
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
