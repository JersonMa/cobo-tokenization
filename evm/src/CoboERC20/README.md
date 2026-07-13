# Cobo ERC20 Tokenization

A sophisticated, upgradeable ERC20 token implementation with role-based access control, built using the Foundry framework and OpenZeppelin's upgradeable contracts.

## 🌟 Features

### Core Token Functionality
- **ERC20 Standard**: Full compliance with ERC20 token standard
- **Upgradeable**: UUPS (Universal Upgradeable Proxy Standard) implementation
- **Multicall Support**: Batch multiple function calls in a single transaction

### Access Control & Security
- **Role-Based Access Control**: Six distinct roles with specific permissions:
  - `DEFAULT_ADMIN_ROLE`: Full administrative control
  - `MINTER_ROLE`: Token minting permissions
  - `BURNER_ROLE`: Token burning permissions
  - `MANAGER_ROLE`: Contract management and token burning from any address
  - `PAUSER_ROLE`: Emergency pause functionality
  - `UPGRADER_ROLE`: Contract upgrade permissions
  - `SALVAGER_ROLE`: Asset recovery capabilities

### Advanced Features
- **Pause/Unpause**: Emergency stop mechanism
- **Access List Control**: Whitelist/blacklist functionality for transfers
- **Asset Salvage**: Recovery of accidentally sent tokens or ETH
- **Contract URI**: Metadata support for contract information

## 🏗️ Architecture

The project uses a modular architecture with the following components:

```
src/
├── CoboERC20/
│   ├── CoboERC20.sol          # Main token contract
│   └── library/
│       ├── Utils/             # Utility contracts
│       └── Errors/            # Error definitions
├── deploy/
    └── ProxyFactory.sol       # Deployment factory
```

## 🔧 Setup

### Prerequisites
- [Foundry](https://getfoundry.sh/) installed
- Node.js and npm (optional, for additional tooling)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd CoboTokenization
   ```

2. **Install dependencies**
   ```bash
   forge install OpenZeppelin/openzeppelin-contracts@v5.3.0 --no-git --shallow
   forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.3.0 --no-git --shallow
   forge install foundry-rs/forge-std --no-git --shallow
   ```

3. **Build the project**
   ```bash
   forge build
   ```

## 🧪 Testing

Run the test suite:
```bash
forge test
```

For verbose output:
```bash
forge test -vvv
```

## 🚀 Deployment

### Manual Deployment

You can also deploy manually by following these steps:

1. Deploy the implementation contract
2. Deploy a proxy pointing to the implementation
3. Initialize the contract with required parameters

### Initialization Parameters

When initializing the contract, provide:
- `name`: Token name (e.g., "CoboERC20")
- `symbol`: Token symbol (e.g., "COBO")
- `uri`: Contract metadata URI
- `decimal`: Token decimal
- `admin`: Initial admin address (receives DEFAULT_ADMIN_ROLE)

## 📋 Usage

### Basic Token Operations

```solidity
// Mint tokens (requires MINTER_ROLE)
coboToken.mint(recipient, amount);

// Burn tokens (requires BURNER_ROLE)
coboToken.burn(amount);

// Burn tokens from specific address (requires MANAGER_ROLE)
coboToken.burnFrom(account, amount);
```

### Access Control

```solidity
// Grant roles (requires DEFAULT_ADMIN_ROLE)
coboToken.grantRole(MINTER_ROLE, minterAddress);

// Check role membership
bool isMinter = coboToken.hasRole(MINTER_ROLE, address);

// Revoke roles
coboToken.revokeRole(MINTER_ROLE, address);
```

### Emergency Controls

```solidity
// Pause the contract (requires PAUSER_ROLE)
coboToken.pause();

// Unpause the contract (requires MANAGER_ROLE)
coboToken.unpause();
```

## 🔐 Security Features

### Role Permissions Matrix

| Role | Mint | Burn Self | Burn Others | Pause | Unpause | Upgrade | Manage Access List | Salvage |
|------|------|-----------|-------------|-------|---------|---------|-------------------|---------|
| MINTER_ROLE | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| BURNER_ROLE | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| MANAGER_ROLE | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ |
| PAUSER_ROLE | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| UPGRADER_ROLE | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| SALVAGER_ROLE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| DEFAULT_ADMIN_ROLE | Grant/Revoke all roles | | | | | | | |

### Access List Control
- Configure allowed/denied addresses for transfers
- Granular control over who can send/receive tokens
- Useful for compliance and regulatory requirements

### Sanctions Screening (on-chain KYC)

A pluggable `sanctionsOracle` (any contract implementing `ISanctionsOracle`, shared at `src/interfaces/`)
provides automated, dynamic address risk screening — e.g. a Chainalysis oracle, an aggregator, or an
internal blacklist. It **complements** the manual `BlockList`: the oracle is a dynamic external feed,
the BlockList remains the manual on-chain override, and both are enforced independently.

Enforcement points (both `CoboERC20` and `CoboERC20Wrapper`):

| Path | Subject |
|------|---------|
| `mint` | `to` |
| `transfer` | `msg.sender` + `to` |
| `transferFrom` | `msg.sender` + `from` + `to` |
| `Wrapper.deposit` | `msg.sender` |
| `Wrapper.withdraw` | `msg.sender` |

Not screened (intentional): `burn` / `burnFrom` are the compliance seizure tools — they must work
against a sanctioned holder, so they bypass screening (same role gating as before).

Controls:
- `setSanctionsOracle(addr)` — `DEFAULT_ADMIN_ROLE` sets/replaces the oracle. Gated at the highest privilege (above the `MANAGER_ROLE` that maintains AccessList/BlockList entries) because it can disable all screening at once. A non-zero candidate is probed once at install (`isSanctioned` is called and its result ignored), so an EOA or non-conforming address reverts here instead of surfacing at the first transfer.
- `setSanctionsOracle(address(0))` — emergency disable (clears the oracle).
- Oracle unset (`address(0)`) ⇒ screening bypassed. A reverting or non-conforming oracle fails closed on normal paths.

Default is off: after an upgrade the oracle is `address(0)` until `DEFAULT_ADMIN_ROLE` installs one.

**Trust boundary (operational).** The install-time probe only proves the candidate is a live contract
exposing a callable `isSanctioned(address)`; it deliberately ignores the returned value, so it does NOT
prove the oracle answers correctly. An on-chain check cannot prove that — it inspects one address at one
instant, while the oracle is external and mutable. A malicious/buggy oracle that returns `true` for
arbitrary addresses could freeze or selectively censor transfers. Security therefore rests on the admin
multisig and the oracle's operator, not on the probe. A reverting or non-conforming oracle is caught at
install; a wrong-but-conforming oracle is not, and it surfaces at the first screened call, which fails
closed. Before installing or replacing an oracle, the runbook MUST:
- confirm the candidate is the expected, audited contract, and whether it is immutable or governance-controlled;
- off-chain verify it returns `false` for a set of known-clean addresses and `true` for known-sanctioned ones;
- keep `setSanctionsOracle(address(0))` ready as the emergency escape hatch if an installed oracle misbehaves.

## ⚙️ Configuration

### Foundry Configuration

The project is configured with:
- Solidity version: 0.8.23
- EVM version: London
- Optimizer: Enabled with 20,000 runs
- IR optimization: Enabled

### Contract Configuration

Key contract settings:
- Upgradeable using UUPS pattern
- Initializer-based setup
- Comprehensive role-based access control

## 🔍 Verification

After deployment, verify your contracts on block explorers:

```bash
forge verify-contract <CONTRACT_ADDRESS> src/CoboERC20/CoboERC20.sol:CoboERC20 --etherscan-api-key <API_KEY>
```

## 📄 License

This project is licensed under LGPL-3.0-only.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## 📞 Support

For questions or support, please contact the Cobo development team at [https://www.cobo.com/](https://www.cobo.com/).

---

Built with ❤️ by the Cobo team
