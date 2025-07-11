// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Configuration structure for a stake type
/// @dev This struct defines all the parameters needed to configure a staking pool
struct StakeConfig {
    address bank; // Address of the bank contract that holds the staked tokens
    address manager; // Address that has management permissions for the stake
    address token; // The ERC20 token address that users can stake
    uint256 interestRate; // Interest rate per year (in wei) - represents the reward rate
    uint256 stakeDuration; // Duration of the stake in seconds - how long tokens must be locked
    uint256 cooldownDuration; // Duration of the cooldown period in seconds after unstaking
    uint256 maxStake; // Maximum amount of tokens that can be staked per user
    uint256 minStake; // Minimum amount of tokens required to stake
    bool isActive; // Whether the stake pool is currently active and accepting deposits
    bool isTopupEnabled; // Whether users can add more tokens to their existing stake
    bool isPublic; // Whether the stake pool is public or restricted to specific users
}

/// @notice Interface for the staking contract to set configuration
/// @dev This interface allows the bank to configure staking pools
interface IStaking {
    function setConfig(
        uint256 _configId,
        StakeConfig calldata _config
    ) external;
}

/// @title Bank Contract
/// @notice A contract that manages token approvals, withdrawals, and staking configurations
/// @dev This contract acts as a treasury/bank that can hold tokens and manage staking pools
contract Bank is OwnableRoles {
    using SafeERC20 for IERC20;

    /// @notice Constructor initializes the contract owner
    /// @dev Sets the deployer as the initial owner of the contract
    constructor() {
        _initializeOwner(msg.sender);
    }

    /// @notice Approves a spender to spend tokens on behalf of this contract
    /// @dev Only the owner can approve token spending
    /// @param _token The ERC20 token address to approve
    /// @param _spender The address that will be approved to spend tokens
    /// @param _amount The amount of tokens to approve for spending
    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).approve(_spender, _amount);
    }

    /// @notice Sets the configuration for a staking pool
    /// @dev Only the owner can configure staking pools, delegates to the staking contract
    /// @param _staking The address of the staking contract
    /// @param _configId The ID of the configuration to set
    /// @param _config The stake configuration parameters
    function setConfig(
        address _staking,
        uint256 _configId,
        StakeConfig calldata _config
    ) external onlyOwner {
        IStaking(_staking).setConfig(_configId, _config);
    }
}
