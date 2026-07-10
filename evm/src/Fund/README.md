# Cobo Fund Tokenization

A NAV-based fund tokenization system that wraps real-world assets into ERC20 share tokens with continuous NAV accrual, built using Foundry and OpenZeppelin v5 upgradeable contracts.

## Architecture

Three-contract system with upgradeable proxy pattern:

```
src/Fund/
├── CoboFundOracle.sol              # NAV oracle with continuous APR accrual (exports ICoboFundOracle)
├── CoboFundToken.sol               # ERC20 share token (mint/redeem/forceRedeem) + sanctions screening config
├── CoboFundVault.sol               # Asset custody vault with settlement (exports ICoboFundToken)
├── interfaces/
│   └── ISanctionsOracle.sol        # Sanctions screening interface (single-method, backend-agnostic)
└── libraries/
    └── LibFundErrors.sol           # Centralized custom errors
```

### Contract Roles

| Contract | Roles |
|----------|-------|
| CoboFundOracle | DEFAULT_ADMIN, NAV_UPDATER, UPGRADER |
| CoboFundToken | DEFAULT_ADMIN, MANAGER, REDEMPTION_APPROVER, EMERGENCY_GUARDIAN, UPGRADER |
| CoboFundVault | DEFAULT_ADMIN, SETTLEMENT_OPERATOR, UPGRADER |

### NAV Formula

```
NAV(t) = baseNetValue + baseNetValue * currentAPR * (t - lastUpdateTimestamp) / (365 days * 1e18)
```

### Sanctions Screening

Optional on-chain compliance screening via a pluggable `ISanctionsOracle` interface (single method `isSanctioned(address) -> bool`). Any backend the operator chooses can plug in — third-party oracle, aggregator, internal blacklist.

Configuration lives on `CoboFundToken.sanctionsOracle`; `CoboFundVault` reads it via `ICoboFundToken` so configuration has a single source of truth. Setting the oracle to `address(0)` disables screening (behavior reverts to a pre-screening fund).

Enforcement points:

| Path | Subject |
|------|---------|
| `mint` | `msg.sender` |
| `requestRedemption` | `msg.sender` |
| `approveRedemption` | stored `user` |
| `rejectRedemption` | stored `user` |
| `transfer` / `transferFrom` | `from` + `to` |
| `Vault.withdraw` | `to` |

Bypass paths (admin-only, intentional):
- `forceRedeem` — burns a sanctioned holder's share balance. Compliance disposal tool, not subject to screening.
- `adminForfeitPending` — clears a pending redemption that cannot be approved or rejected (user listed between request and settlement).

Operational controls (admin-only):
- `setSanctionsOracle(addr)` — install or replace the oracle.
- `setSanctionsOracle(address(0))` — emergency disable.

## Testing

```bash
# All tests (excluding fuzz for speed)
forge test --match-path "test/Fund/*" --no-match-path "test/Fund/FundFuzz.t.sol"

# Full suite including fuzz
forge test --match-path "test/Fund/*"
```

Test files:
- `CoboFundOracle.t.sol` — Oracle unit tests
- `CoboFundToken.t.sol` — Share token unit tests
- `CoboFundVault.t.sol` — Vault unit tests
- `FundIntegration.t.sol` — Cross-contract integration
- `FundNumerical.t.sol` — Precision and boundary
- `FundSecurity.t.sol` — Attack scenarios
- `FundSanctions.t.sol` — Sanctions screening enforcement and emergency controls
- `FundFuzz.t.sol` — Fuzz and invariant
- `FundUpgrade.t.sol` — UUPS upgrade

## Deployment

Deploy logic contracts once, then deploy multiple product instances with different underlying assets.

### Step 1: Deploy logic contracts

```bash
forge script script/DeployFundLogic.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify

# Save the output addresses
export ORACLE_LOGIC=0x...
export FUNDTOKEN_LOGIC=0x...
export VAULT_LOGIC=0x...
```

### Step 2: Deploy Mock ERC20 (Testnet only)

```bash
# Deploy mock asset token
forge script script/DeployMockERC20.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast

export ASSET_TOKEN=0x...
```

**Note**: Edit `script/DeployMockERC20.s.sol` to change token parameters for different assets (WBTC, etc.).

### Step 3: Configure product parameters

```bash
# Token configuration
export TOKEN_NAME="Example Fund Token"
export TOKEN_SYMBOL="EFT"
export TOKEN_DECIMALS=18
export UNDERLYING_TOKEN=$ASSET_TOKEN

# Oracle configuration
export INITIAL_NAV=1000000000000000000      # 1e18
export INITIAL_APR=0
export MAX_APR=200000000000000000           # 20%
export MAX_APR_DELTA=50000000000000000      # 5%
export MIN_UPDATE_INTERVAL=86400            # 1 day

# Limits
export MIN_DEPOSIT_AMOUNT=1000000           # 1 unit (6 decimals)
export MIN_REDEEM_SHARES=1000000000000000000 # 1 share (18 decimals)

# Roles
export ADMIN=0x...
export NAV_UPDATER=0x...
export MANAGER=0x...
export REDEMPTION_APPROVER=0x...
export SETTLEMENT_OPERATOR=0x...

# Optional: sanctions screening oracle (any ISanctionsOracle-compatible contract).
# Unset = skip; admin can install later via setSanctionsOracle.
# export SANCTIONS_ORACLE=0x...
```

### Step 4: Deploy product proxy

```bash
forge script script/DeployFundProxyTemplate.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify

# Extract addresses from output
export ORACLE_PROXY=0x...
export FUNDTOKEN_PROXY=0x...
export VAULT_PROXY=0x...
```

### Step 5: Configure roles

```bash
forge script script/PostDeployConfig.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Grants roles from Step 3 to their respective addresses and installs the sanctions oracle if `SANCTIONS_ORACLE` is set (optional).

**To deploy additional products**: Repeat Steps 3-5 with different parameters (e.g., TOKEN_SYMBOL="XBTC").

## Deployment Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `DeployFundLogic.s.sol` | Deploy logic contracts | Once per deployment |
| `DeployFundProxyTemplate.s.sol` | Deploy product proxy | Once per product |
| `DeployMockERC20.s.sol` | Deploy mock ERC20 tokens | Testnet only |
| `PostDeployConfig.s.sol` | Configure roles and whitelist | Once per product |

### Detailed Instructions

See `/tmp/fund-deployment-commands.md` for complete step-by-step deployment guide with troubleshooting.

## License

LGPL-3.0-only
