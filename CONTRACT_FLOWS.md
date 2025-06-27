# OpenLedger Contracts - Flow Documentation

This document describes the flows and functionality of the two main contracts in the OpenLedger system: `BaseDistributor` and `Staking`.

## Table of Contents

1. [BaseDistributor Contract](#basedistributor-contract)
   - [Overview](#overview)
   - [Key Components](#key-components)
   - [Flow Diagrams](#flow-diagrams)
   - [Admin Functions](#admin-functions)
   - [User Functions](#user-functions)

2. [Staking Contract](#staking-contract)
   - [Overview](#overview-1)
   - [Key Components](#key-components-1)
   - [Flow Diagrams](#flow-diagrams-1)
   - [Admin Functions](#admin-functions-1)
   - [User Functions](#user-functions-1)
   - [Stake Lifecycle](#stake-lifecycle)

---

## BaseDistributor Contract

### Overview

The `BaseDistributor` contract is a flexible airdrop distribution system that allows users to claim tokens based on cryptographic signatures. It implements a secure claim mechanism with optional signature verification and supports claiming on behalf of other addresses.

### Key Components

- **Signer**: Address authorized to sign claim messages
- **Vault**: Address holding the tokens to be distributed
- **Token**: ERC20 token being distributed
- **Active State**: Boolean flag controlling whether claims are allowed
- **Claimed Mapping**: Tracks claimed amounts per root and address

### Flow Diagrams

#### Contract Initialization Flow
```
Deployer → Constructor
    ↓
Set Signer, Project Admin, Vault
    ↓
Initialize Owner (msg.sender)
    ↓
Set Project Admin Role
    ↓
Contract Ready
```

#### Claim Flow
```
User → claim(signature, amount, onBehalfOf)
    ↓
Check if contract is active
    ↓
If signer is set:
    Verify signature validity
    ↓
Transfer tokens from vault to onBehalfOf
    ↓
Emit AirdropClaimed event
```

#### Signature Verification Flow
```
Input: amount, onBehalfOf, signature, signer
    ↓
Create message hash: keccak256(onBehalfOf, amount, bytes32(0), contract, chainId)
    ↓
Add Ethereum signed message prefix
    ↓
Recover signer from signature
    ↓
Compare with expected signer
    ↓
Revert if mismatch
```

### Admin Functions

#### `setSigner(address _signer)`
- **Access**: PROJECT_ADMIN role only
- **Purpose**: Updates the authorized signer address
- **Flow**: Direct state update

#### `setVault(address _vault)`
- **Access**: PROJECT_ADMIN role only
- **Purpose**: Updates the vault address holding tokens
- **Flow**: Updates state and emits VaultSet event

#### `toggleActive()`
- **Access**: PROJECT_ADMIN role only
- **Purpose**: Toggles the active state of the contract
- **Flow**: Flips boolean state

#### `setToken(address _token)`
- **Access**: PROJECT_ADMIN role only
- **Purpose**: Sets the ERC20 token address for distribution
- **Flow**: Updates state and emits TokenSet event

### User Functions

#### `claim(bytes calldata _signature, uint256 _amount, address _onBehalfOf)`
- **Access**: Public (when active)
- **Purpose**: Claims airdrop tokens
- **Flow**:
  1. Verify contract is active
  2. If signer is set, verify signature
  3. Transfer tokens from vault to onBehalfOf
  4. Emit claim event

---

## Staking Contract

### Overview

The `Staking` contract is a sophisticated staking system that allows users to stake tokens and earn interest over time. It supports multiple stake configurations, commitment-based staking, and flexible unstaking with optional cooldown periods.

### Key Components

- **Stake**: Individual staking position with recipient, config, timing, and amount
- **StakeConfig**: Configuration defining interest rates, durations, limits, and features
- **StakeCommitment**: Commitment-based staking with cryptographic proofs
- **UnstakeRequest**: Pending unstake requests during cooldown periods

### Flow Diagrams

#### Stake Configuration Flow
```
Manager → setConfig(configId, config)
    ↓
Verify manager == msg.sender
    ↓
Store configuration
    ↓
Emit ConfigSet event
```

#### Standard Staking Flow
```
User → stake(configId, onBehalfOf, amount)
    ↓
Load stake configuration
    ↓
Verify config is active
    ↓
Transfer tokens from user to bank
    ↓
Create new stake record
    ↓
Update staked amounts
    ↓
Validate min/max stake limits
    ↓
Emit Staked event
```

#### Commitment-Based Staking Flow
```
User → commitStake(commitment, permit)
    ↓
Store commitment with signature
    ↓
Emit CommitStake event
    ↓
Later: requestUnstakeWithCommitment
    ↓
Verify commitment signature from config.manager
    ↓
Open commitment into actual stake
    ↓
Proceed with unstake request
```

#### Unstaking Flow
```
User → requestUnstake(stakingId)
    ↓
Load stake and verify ownership
    ↓
Accrue interest
    ↓
Delete stake record
    ↓
If cooldown = 0:
    → Immediate unstake
Else:
    → Create unstake request
    → Emit RequestUnstake event
```

#### Cooldown Unstaking Flow
```
User → unstake(stakingId)
    ↓
Load unstake request
    ↓
Verify ownership and cooldown passed
    ↓
Delete unstake request
    ↓
Execute unstake
```

### Admin Functions

#### `setConfig(uint256 _configId, StakeConfig calldata _config)`
- **Access**: Only the config manager
- **Purpose**: Sets or updates stake configuration
- **Flow**:
  1. Verify msg.sender is the config manager
  2. Store configuration
  3. Emit ConfigSet event

```solidity
/// @notice Configuration for a stake type
struct StakeConfig {
    address manager; // Address that can manage the stake
    address bank; // Address that holds the staked tokens
    address token; // The token that users can stake
    uint256 interestRate; // Interest rate per second (in wei)
    uint256 stakeDuration; // Duration of the stake in seconds
    uint256 cooldownDuration; // Duration of the cooldown period in seconds

    uint256 maxStake; // Maximum amount of tokens that can be staked
    uint256 minStake; // Minimum amount of tokens that can be staked
    bool isActive; // Whether the stake is active
    bool isTopupEnabled; // Whether the stake is topped up
}
```

### User Functions

#### `stake(uint256 _configId, address _onBehalfOf, uint256 _amount)`
- **Access**: Public
- **Purpose**: Creates a new stake
- **Flow**:
  1. Load and verify config is active
  2. Transfer tokens from user to bank
  3. Create stake record
  4. Update staked amounts
  5. Validate limits
  6. Emit Staked event

#### `commitStake(bytes32 _commitment, bytes calldata _permit)`
- **Access**: Public
- **Purpose**: Creates a commitment-based stake
- **Flow**:
  1. Store commitment with signature
  2. Emit CommitStake event

#### `topUpStake(uint256 _stakingId, uint256 _amount)`
- **Access**: Stake recipient only
- **Purpose**: Adds more tokens to existing stake
- **Flow**:
  1. Verify config allows top-ups
  2. Verify caller is stake recipient
  3. Transfer additional tokens
  4. Accrue existing interest
  5. Update stake with new amount
  6. Reset timing
  7. Emit ToppedUp event

#### `requestUnstakeWithCommitment(uint256 _stakingId, uint256 _configId, uint256 _startTime, uint256 _amount, uint256 _nonce)`
- **Access**: Public
- **Purpose**: Opens commitment and requests unstake
- **Flow**:
  1. Load commitment
  2. Verify EIP-712 signature
  3. Delete commitment
  4. Create actual stake
  5. Request unstake

```solidity
/// @notice EIP712 structure for signature verification
struct Stake {
    uint256 configId;
    uint256 amount;
    uint256 startTime;
    uint256 nonce;
}
```

#### `requestUnstake(uint256 _stakingId)`
- **Access**: Stake recipient only
- **Purpose**: Initiates unstaking process
- **Flow**:
  1. Load stake and verify ownership
  2. Accrue interest
  3. Delete stake record
  4. If no cooldown: immediate unstake
  5. If cooldown: create unstake request

#### `unstake(uint256 _stakingId)`
- **Access**: Stake recipient only
- **Purpose**: Completes unstaking after cooldown
- **Flow**:
  1. Load unstake request
  2. Verify ownership and cooldown passed
  3. Delete request
  4. Execute unstake

### Stake Lifecycle

#### 1. Configuration Setup
- Manager sets stake configuration with parameters
- Config includes interest rates, durations, limits, and features

#### 2. Staking Phase
- Users stake tokens according to configuration
- Interest accrues continuously based on time and rate
- Users can top up existing stakes (if enabled)

#### 3. Interest Accrual
- Interest calculated as: `amount * interestRate * elapsedTime`
- Interest capped by stake duration
- Interest tracked separately from principal

#### 4. Unstaking Phase
- Users request unstake
- If cooldown configured: wait period required
- If no cooldown: immediate unstake
- Stake must be at least `stakeDuration` old

#### 5. Token Return
- Principal + accrued interest returned to user
- Tokens transferred from bank to user
- Stake record deleted

### Key Features

#### Commitment-Based Staking
- Users can commit to stakes before actual token transfer
- Cryptographic proofs ensure commitment integrity
- Useful for privacy and gas optimization

#### Flexible Configuration
- Multiple stake types with different parameters
- Configurable interest rates, durations, and limits
- Optional features like top-ups and cooldowns

#### Security Features
- EIP-712 typed data signing
- Access control via OwnableRoles
- Reentrancy protection
- Comprehensive validation checks

#### Interest Calculation
- Continuous interest accrual
- Fixed-point math for precision
- Time-based calculation with duration caps 