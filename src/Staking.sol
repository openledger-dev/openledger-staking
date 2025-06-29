// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

/// @title Staking Contract
/// @notice A flexible staking system that allows users to stake tokens and earn interest
/// @dev Implements EIP-712 for typed data signing and uses Solady's OwnableRoles for access control
struct Stake {
    address recipient; // Commitment to the stake
    uint256 configId; // Configuration ID
    uint256 claimAt; // Timestamp of the last interest claim
    uint256 accruedInterest; // Accumulated interest that hasn't been claimed
    uint256 amount; // Amount of tokens staked
    uint256 startTime; // Timestamp when the stake was created
}

/// @notice Configuration for a stake type
struct StakeConfig {
    address bank; // Address that holds the staked tokens
    address manager; // Address that can manage the stake
    address token; // The token that users can stake
    uint256 interestRate; // Interest rate per second (in wei)
    uint256 stakeDuration; // Duration of the stake in seconds
    uint256 cooldownDuration; // Duration of the cooldown period in seconds
    uint256 maxStake; // Maximum amount of tokens that can be staked
    uint256 minStake; // Minimum amount of tokens that can be staked
    bool isActive; // Whether the stake is active
    bool isTopupEnabled; // Whether the stake is topped up
    bool isPublic; // Whether the stake is public
}

/// @notice Represents an unstake request with timing information
struct UnstakeRequest {
    uint256 requestAt; // Timestamp when the unstake was requested
    Stake stake; // The stake being unstaked
}

/// @title Staking
/// @notice A flexible staking system that allows users to stake tokens and earn interest
contract Staking is EIP712, OwnableRoles {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /// @notice Mapping of stake ID to stake information
    mapping(uint256 => Stake) public stakes;
    mapping(uint256 => bytes) public stakeCommitments;
    /// @notice Counter for generating unique stake IDs
    uint256 public nextStakeId;

    /// @notice Mapping of stake ID to unstake requests
    mapping(uint256 => UnstakeRequest) public unstakeRequests;

    /// @notice Mapping of configuration hash to enabled features
    mapping(uint256 => StakeConfig) public configs;
    mapping(uint256 => mapping(address => uint256)) public stakedAmounts;

    mapping(bytes32 => bool) public replayGuard;

    event Staked(uint256 indexed stakingId, address indexed recipient, uint256 indexed amount);
    event ToppedUp(uint256 indexed stakingId, address indexed recipient, uint256 amount);
    event Unstaked(uint256 indexed stakingId, address indexed recipient);
    event RequestUnstake(uint256 indexed stakingId, address indexed recipient);
    event ConfigSet(uint256 indexed configId);
    event ConfigCreated(uint256 indexed configId);
    event CommitStake(uint256 indexed stakingId, bytes commitment);

    error InactiveConfigOrInvalidSender();
    error StakeNotFound();
    error UnstakeRequestNotFound();
    error CooldownNotPassed();
    error ZeroAmount();
    error StakeNotEnded();
    error StakeEnded();
    error StakeAmountExceeded();
    error StakeAmountTooSmall();
    error MismatchedRecipient();
    error InvalidCommitment();
    error SignatureReplayed();

    uint256 public constant TRUSTED_BANK = _ROLE_0;

    /// @notice Creates a new staking contract
    /// @dev Initializes the contract with the deployer as the owner
    constructor() {
        _initializeOwner(msg.sender);
    }

    /// @notice Ensures the amount is greater than zero
    /// @param _amount The amount to check
    modifier nonZeroAmount(uint256 _amount) {
        if (_amount == 0) {
            revert ZeroAmount();
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Admin Functions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setConfig(uint256 _configId, StakeConfig calldata _config) external onlyRoles(TRUSTED_BANK) {
        StakeConfig memory config_ = configs[_configId];

        // Create config
        if (config_.bank == address(0)) {
            StakeConfig memory newConfig_ = StakeConfig({
                bank: msg.sender,
                manager: _config.manager,
                token: _config.token,
                interestRate: _config.interestRate,
                stakeDuration: _config.stakeDuration,
                cooldownDuration: _config.cooldownDuration,
                maxStake: _config.maxStake,
                minStake: _config.minStake,
                isActive: _config.isActive,
                isTopupEnabled: _config.isTopupEnabled,
                isPublic: _config.isPublic
            });
            configs[_configId] = newConfig_;
            emit ConfigCreated(_configId);
            return;
        }

        // Update config
        if (config_.bank != msg.sender) {
            revert Unauthorized();
        }
        configs[_configId] = _config;
        emit ConfigSet(_configId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     External Functions                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Allows a user to stake tokens
    /// @param _configId The configuration for the stake (duration, interest rate, whitelist)
    /// @param _onBehalfOf The address that will receive the staked tokens and interest
    /// @param _amount The amount of tokens to stake
    /// @dev SECURITY:
    /// @dev - Front-running: Safe because token transfer is from msg.sender
    /// @dev - Reentrancy: Safe because transfer is done after state mutation
    /// @dev - Access control: Checks whitelist if configured
    function stake(uint256 _configId, address _onBehalfOf, uint256 _amount) external nonZeroAmount(_amount) {
        StakeConfig memory config_ = configs[_configId];

        if (!config_.isActive) {
            revert InactiveConfigOrInvalidSender();
        }

        if (!config_.isPublic) {
            revert InactiveConfigOrInvalidSender();
        }

        IERC20(config_.token).safeTransferFrom(msg.sender, config_.bank, _amount);

        Stake memory stake_ = Stake({
            recipient: _onBehalfOf,
            configId: _configId,
            claimAt: block.timestamp,
            accruedInterest: 0,
            amount: _amount,
            startTime: block.timestamp
        });

        uint256 currentStakeId_ = nextStakeId++;

        stakes[currentStakeId_] = stake_;

        uint256 newStakedAmount_ = stakedAmounts[_configId][_onBehalfOf] + _amount;

        if (newStakedAmount_ <= config_.minStake) {
            revert StakeAmountTooSmall();
        }

        if (newStakedAmount_ >= config_.maxStake) {
            revert StakeAmountExceeded();
        }

        stakedAmounts[_configId][_onBehalfOf] = newStakedAmount_;

        emit Staked(currentStakeId_, _onBehalfOf, _amount);
    }

    function commitStake(bytes calldata _permit) external {
        bytes32 digest = keccak256(_permit);
        if (replayGuard[digest]) {
            revert SignatureReplayed();
        }
        replayGuard[digest] = true;

        uint256 currentStakeId_ = nextStakeId++;
        stakeCommitments[currentStakeId_] = _permit;

        emit CommitStake(currentStakeId_, _permit);
    }

    /// @notice Allows topping up an existing stake
    /// @param _stakingId The ID of the stake to top up
    /// @param _amount The amount of tokens to add to the stake
    /// @dev SECURITY:
    /// @dev - Reentrancy: Safe because transfer is done after state mutation
    /// @dev - Access control: Only allowed if TOPUP_ENABLED is set for the stake config
    function topUpStake(uint256 _stakingId, uint256 _amount) external nonZeroAmount(_amount) {
        Stake memory stake_ = stakes[_stakingId];
        StakeConfig memory config_ = configs[stake_.configId];

        // Stake exists otherwise will revert
        if (stake_.amount == 0 || stake_.recipient != msg.sender || !config_.isTopupEnabled) {
            revert InactiveConfigOrInvalidSender();
        }

        bool isEnded_ = stake_.startTime + config_.stakeDuration <= block.timestamp;
        if (isEnded_) {
            revert StakeEnded();
        }

        IERC20(config_.token).safeTransferFrom(msg.sender, config_.bank, _amount);

        uint256 interest = calculateInterest(stake_);

        stake_.amount += interest + _amount;
        stake_.startTime = block.timestamp;
        stake_.claimAt = block.timestamp;
        stake_.accruedInterest = 0;

        stakedAmounts[stake_.configId][stake_.recipient] += _amount + interest;

        if (stakedAmounts[stake_.configId][stake_.recipient] >= config_.maxStake) {
            revert StakeAmountExceeded();
        }

        stakes[_stakingId] = stake_;

        emit ToppedUp(_stakingId, stake_.recipient, _amount);
    }

    function requestUnstakeWithCommitment(
        uint256 _stakingId,
        uint256 _configId,
        uint256 _startTime,
        uint256 _nonce,
        uint256 _amount
    ) external {
        bytes memory commitment_ = stakeCommitments[_stakingId];
        if (commitment_.length == 0) {
            revert StakeNotFound();
        }

        bytes32 digest = _hashTypedData(
            keccak256(
                abi.encode(
                    keccak256(
                        "Stake(address recipient,uint256 configId,uint256 amount,uint256 startTime,uint256 nonce)"
                    ),
                    msg.sender,
                    _configId,
                    _startTime,
                    _amount,
                    _nonce
                )
            )
        );

        StakeConfig memory config_ = configs[_configId];

        address signer = ECDSA.recover(digest, commitment_);

        if (signer != config_.manager) {
            revert Unauthorized();
        }

        // Open commitment
        delete stakeCommitments[_stakingId];
        Stake memory stake_ = Stake({
            recipient: msg.sender,
            configId: _configId,
            claimAt: _startTime,
            accruedInterest: 0,
            amount: _amount,
            startTime: _startTime
        });
        stakes[_stakingId] = stake_;
        stakedAmounts[_configId][msg.sender] += _amount;

        requestUnstake(_stakingId);
    }

    /// @notice Initiates the unstaking process for a stake
    /// @param _stakingId The ID of the stake to unstake
    /// @dev If cooldown is not required, unstakes immediately
    /// @dev If cooldown is required, creates an unstake request
    function requestUnstake(uint256 _stakingId) public {
        Stake memory stake_ = stakes[_stakingId];
        if (stake_.amount == 0) {
            revert StakeNotFound();
        }

        if (stake_.recipient != msg.sender) {
            revert MismatchedRecipient();
        }

        stake_ = accureInterest(stake_);
        delete stakes[_stakingId];

        StakeConfig memory config_ = configs[stake_.configId];

        if (config_.cooldownDuration == 0) {
            inner_unstake(_stakingId, stake_);
        } else {
            unstakeRequests[_stakingId] = UnstakeRequest({requestAt: block.timestamp, stake: stake_});
            emit RequestUnstake(_stakingId, stake_.recipient);
        }
    }

    /// @notice Completes the unstaking process after cooldown period
    /// @param _stakingId The ID of the stake to unstake
    /// @dev Can only be called after the cooldown period has passed
    function unstake(uint256 _stakingId) external {
        UnstakeRequest memory unstakeRequest_ = unstakeRequests[_stakingId];
        StakeConfig memory config_ = configs[unstakeRequest_.stake.configId];
        if (unstakeRequest_.requestAt == 0) {
            revert UnstakeRequestNotFound();
        }

        if (unstakeRequest_.stake.recipient != msg.sender) {
            revert MismatchedRecipient();
        }

        if (block.timestamp < unstakeRequest_.requestAt + config_.cooldownDuration) {
            revert CooldownNotPassed();
        }
        delete unstakeRequests[_stakingId];
        inner_unstake(_stakingId, unstakeRequest_.stake);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Internal Functions                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Internal function to handle unstaking logic
    /// @param _stakeId The ID of the stake to unstake
    /// @param _stake The stake information
    function inner_unstake(uint256 _stakeId, Stake memory _stake) internal {
        StakeConfig memory config_ = configs[_stake.configId];
        bool isEnded_ = _stake.startTime + config_.stakeDuration <= block.timestamp;
        if (!isEnded_) {
            revert StakeNotEnded();
        }

        stakedAmounts[_stake.configId][_stake.recipient] -= _stake.amount;

        IERC20(config_.token).safeTransferFrom(config_.bank, _stake.recipient, _stake.amount + _stake.accruedInterest);
        emit Unstaked(_stakeId, _stake.recipient);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       View Functions                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Calculates and accrues interest for a stake
    /// @param _stake The stake to accrue interest for
    /// @return _stake The stake with accrued interest
    function accureInterest(Stake memory _stake) public view returns (Stake memory) {
        uint256 interest = calculateInterest(_stake);
        _stake.accruedInterest = interest;
        _stake.claimAt = block.timestamp;
        return _stake;
    }

    /// @notice Calculates the interest earned for a stake
    /// @param _stakeInfo The stake information
    /// @return uint256 The amount of interest earned
    function calculateInterest(Stake memory _stakeInfo) public view returns (uint256) {
        uint256 claimAt_ = _stakeInfo.claimAt;
        StakeConfig memory config_ = configs[_stakeInfo.configId];
        uint256 stakeDuration_ = config_.stakeDuration;
        uint256 interestRate_ = config_.interestRate;
        uint256 amount_ = _stakeInfo.amount;

        uint256 elapsedTime_ = block.timestamp - claimAt_;
        uint256 upperBound_ = (stakeDuration_ == 0) ? type(uint256).max : stakeDuration_;
        elapsedTime_ = elapsedTime_ > upperBound_ ? upperBound_ : elapsedTime_;

        uint256 interest_ = amount_.mulWad(interestRate_ * elapsedTime_);
        return interest_ + _stakeInfo.accruedInterest;
    }

    function _domainNameAndVersion()
        internal
        view
        virtual
        override
        returns (string memory name, string memory version)
    {
        return ("Staking", "1");
    }
}
