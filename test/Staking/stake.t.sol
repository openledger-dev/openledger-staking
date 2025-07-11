// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {Staking, Stake, StakeConfig} from "../../src/Staking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint8 public decimals = 18;
    string public name = "Mock Token";
    string public symbol = "MTK";

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract StakeTest is Test {
    Staking public staking;
    MockERC20 public token;

    address public user = address(0x1);
    address public user2 = address(0x2);
    address public bank = address(0x3);
    address public bank2 = address(0x4);
    address public manager = address(0x5);

    uint256 public constant WAD = 1e18;
    uint256 public constant CONFIG_ID = 1;
    uint256 public constant CONFIG_ID_2 = 2;
    uint256 public constant CONFIG_ID_3 = 3;

    // Test configuration
    uint256 public constant STAKE_AMOUNT = 1000 * WAD; // 1000 tokens
    uint256 public constant INTEREST_RATE = 5e16;
    uint256 public constant STAKE_DURATION = 365 days;
    uint256 public constant COOLDOWN_DURATION = 7 days;
    uint256 public constant MAX_STAKE = 10000 * WAD;
    uint256 public constant MIN_STAKE = 100 * WAD;

    function setUp() public {
        staking = new Staking();
        token = new MockERC20();

        // Setup bank role
        staking.grantRoles(bank, staking.TRUSTED_BANK());
        staking.grantRoles(bank2, staking.TRUSTED_BANK());

        // Create active and public stake configuration
        StakeConfig memory config = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: INTEREST_RATE,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(CONFIG_ID, config);

        // Create inactive configuration
        StakeConfig memory inactiveConfig = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: INTEREST_RATE,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: false,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(CONFIG_ID_2, inactiveConfig);

        // Create non-public configuration
        StakeConfig memory privateConfig = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: INTEREST_RATE,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: false
        });

        vm.prank(bank);
        staking.setConfig(CONFIG_ID_3, privateConfig);

        // Mint tokens to users and banks
        token.mint(user, STAKE_AMOUNT * 10);
        token.mint(user2, STAKE_AMOUNT * 10);
        token.mint(bank, STAKE_AMOUNT * 100);
        token.mint(bank2, STAKE_AMOUNT * 100);

        // Approve staking contract
        vm.prank(user);
        token.approve(address(staking), type(uint256).max);

        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);

        vm.prank(bank);
        token.approve(address(staking), type(uint256).max);

        vm.prank(bank2);
        token.approve(address(staking), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // Zero Amount Tests
    // -------------------------------------------------------------------------

    function test_RevertWhen_StakeZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(Staking.ZeroAmount.selector);
        staking.stake(CONFIG_ID, user, 0);
    }

    function test_RevertWhen_TopupZeroAmount() public {
        // First create a stake
        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        // Try to topup with zero amount
        vm.prank(user);
        vm.expectRevert(Staking.ZeroAmount.selector);
        staking.topUpStake(0, 0); // stake ID 0
    }

    // -------------------------------------------------------------------------
    // Unauthorized Bank Update Tests
    // -------------------------------------------------------------------------

    function test_RevertWhen_UnauthorizedBankUpdatesConfig() public {
        StakeConfig memory config = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: INTEREST_RATE,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        // bank2 tries to update bank's config
        vm.prank(bank2);
        vm.expectRevert(Ownable.Unauthorized.selector);
        staking.setConfig(CONFIG_ID, config);
    }

    function test_RevertWhen_NonBankUpdatesConfig() public {
        StakeConfig memory config = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: INTEREST_RATE,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        // user tries to update config
        vm.prank(user);
        vm.expectRevert(Ownable.Unauthorized.selector);
        staking.setConfig(CONFIG_ID, config);
    }

    // -------------------------------------------------------------------------
    // Non-Active/Non-Public Plan Tests
    // -------------------------------------------------------------------------

    function test_RevertWhen_StakeOnInactiveConfig() public {
        vm.prank(user);
        vm.expectRevert(Staking.InactiveConfigOrInvalidSender.selector);
        staking.stake(CONFIG_ID_2, user, STAKE_AMOUNT);
    }

    function test_RevertWhen_StakeOnNonPublicConfig() public {
        vm.prank(user);
        vm.expectRevert(Staking.InactiveConfigOrInvalidSender.selector);
        staking.stake(CONFIG_ID_3, user, STAKE_AMOUNT);
    }

    function test_RevertWhen_StakeOnPlanToggledInactive() public {
        // Toggle plan to inactive
        (
            address bank_,
            address manager_,
            address token_,
            uint256 interestRate_,
            uint256 stakeDuration_,
            uint256 cooldownDuration_,
            uint256 maxStake_,
            uint256 minStake_,
            bool isActive_,
            bool isTopupEnabled_,
            bool isPublic_
        ) = staking.configs(CONFIG_ID);
        StakeConfig memory config = StakeConfig({
            bank: bank_,
            manager: manager_,
            token: token_,
            interestRate: interestRate_,
            stakeDuration: stakeDuration_,
            cooldownDuration: cooldownDuration_,
            maxStake: maxStake_,
            minStake: minStake_,
            isActive: false,
            isTopupEnabled: isTopupEnabled_,
            isPublic: isPublic_
        });
        vm.prank(bank);
        staking.setConfig(CONFIG_ID, config);

        // Try to stake
        vm.prank(user);
        vm.expectRevert(Staking.InactiveConfigOrInvalidSender.selector);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);
    }

    function test_Success_TopupOnInactivePlan() public {
        // User creates a stake while plan is active
        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        // Toggle plan to inactive
        (
            address bank_,
            address manager_,
            address token_,
            uint256 interestRate_,
            uint256 stakeDuration_,
            uint256 cooldownDuration_,
            uint256 maxStake_,
            uint256 minStake_,
            bool isActive_,
            bool isTopupEnabled_,
            bool isPublic_
        ) = staking.configs(CONFIG_ID);
        StakeConfig memory config = StakeConfig({
            bank: bank_,
            manager: manager_,
            token: token_,
            interestRate: interestRate_,
            stakeDuration: stakeDuration_,
            cooldownDuration: cooldownDuration_,
            maxStake: maxStake_,
            minStake: minStake_,
            isActive: false,
            isTopupEnabled: isTopupEnabled_,
            isPublic: isPublic_
        });
        vm.prank(bank);
        staking.setConfig(CONFIG_ID, config);

        // User can still top up
        uint256 topupAmount = 200 * WAD;
        vm.prank(user);
        staking.topUpStake(0, topupAmount);
        assertEq(
            staking.stakedAmounts(CONFIG_ID, user),
            STAKE_AMOUNT + topupAmount,
            "User should be able to topup on inactive plan"
        );
    }

    // -------------------------------------------------------------------------
    // Stake Amount Tests
    // -------------------------------------------------------------------------

    function test_RevertWhen_StakeAmountTooSmall() public {
        uint256 smallAmount = MIN_STAKE - 1;
        vm.prank(user);
        vm.expectRevert(Staking.StakeAmountTooSmall.selector);
        staking.stake(CONFIG_ID, user, smallAmount);
    }

    function test_RevertWhen_StakeAmountExceedsMax() public {
        // Give user more tokens for this test
        token.mint(user, MAX_STAKE);

        // First stake a small amount, then try to stake the remaining that would exceed max
        uint256 firstStake = 100 * WAD;
        vm.prank(user);
        staking.stake(CONFIG_ID, user, firstStake);

        // Now try to stake an amount that would exceed max
        uint256 remainingToMax = MAX_STAKE - firstStake + 1;
        vm.prank(user);
        vm.expectRevert(Staking.StakeAmountExceeded.selector);
        staking.stake(CONFIG_ID, user, remainingToMax);
    }

    function test_Success_StakeMinimumAmount() public {
        vm.prank(user);
        staking.stake(CONFIG_ID, user, MIN_STAKE + 1);

        assertEq(staking.stakedAmounts(CONFIG_ID, user), MIN_STAKE + 1, "Staked amount should be above minimum stake");
    }

    function test_Success_StakeMaximumAmount() public {
        vm.prank(user);
        staking.stake(CONFIG_ID, user, MAX_STAKE - 1);

        assertEq(staking.stakedAmounts(CONFIG_ID, user), MAX_STAKE - 1, "Staked amount should be below maximum stake");
    }

    function test_RevertWhen_StakeExceedsMaxAfterTopup() public {
        // First stake an amount that would exceed max when topped up
        uint256 firstStake = MAX_STAKE - 100;
        vm.prank(user);
        staking.stake(CONFIG_ID, user, firstStake);

        // Try to topup with amount that would exceed max (user has 100 tokens left)
        vm.prank(user);
        vm.expectRevert(Staking.StakeAmountExceeded.selector);
        staking.topUpStake(0, 100); // stake ID 0, would make total = MAX_STAKE, which should fail
    }

    // -------------------------------------------------------------------------
    // Topup Tests
    // -------------------------------------------------------------------------

    function test_RevertWhen_TopupWithNonOwnAccount() public {
        // First create a stake
        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        // user2 tries to topup user's stake
        vm.prank(user2);
        vm.expectRevert(Staking.InactiveConfigOrInvalidSender.selector);
        staking.topUpStake(0, STAKE_AMOUNT); // stake ID 0
    }

    function test_RevertWhen_TopupNonExistentStake() public {
        vm.prank(user);
        vm.expectRevert(Staking.InactiveConfigOrInvalidSender.selector);
        staking.topUpStake(999, STAKE_AMOUNT); // non-existent stake ID
    }

    function test_RevertWhen_TopupStakeWithTopupDisabled() public {
        // Create config with topup disabled
        StakeConfig memory noTopupConfig = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: INTEREST_RATE,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: false,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(4, noTopupConfig);

        // Create stake with topup disabled
        vm.prank(user);
        staking.stake(4, user, STAKE_AMOUNT);

        // Try to topup
        vm.prank(user);
        vm.expectRevert(Staking.InactiveConfigOrInvalidSender.selector);
        staking.topUpStake(0, STAKE_AMOUNT); // stake ID 0
    }

    function test_RevertWhen_TopupEndedStake() public {
        // Create stake
        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        // Advance time past stake duration
        vm.warp(block.timestamp + STAKE_DURATION + 1);

        // Try to topup ended stake
        vm.prank(user);
        vm.expectRevert(Staking.StakeEnded.selector);
        staking.topUpStake(0, STAKE_AMOUNT); // stake ID 0
    }

    function test_Success_TopupStake() public {
        // Create stake
        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        uint256 topupAmount = 500 * WAD;

        // Topup stake
        vm.prank(user);
        staking.topUpStake(0, topupAmount); // stake ID 0

        // Check that staked amount increased
        assertEq(
            staking.stakedAmounts(CONFIG_ID, user), STAKE_AMOUNT + topupAmount, "Staked amount should include topup"
        );
    }

    // -------------------------------------------------------------------------
    // Unstake Tests
    // -------------------------------------------------------------------------

    function test_RevertWhen_RequestUnstakeNonExistentStake() public {
        vm.prank(user);
        vm.expectRevert(Staking.StakeNotFound.selector);
        staking.requestUnstake(999);
    }

    function test_RevertWhen_RequestUnstakeWithWrongRecipient() public {
        // Create stake for user
        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        // user2 tries to request unstake
        vm.prank(user2);
        vm.expectRevert(Staking.MismatchedRecipient.selector);
        staking.requestUnstake(0); // stake ID 0
    }

    function test_RevertWhen_UnstakeBeforeCooldown() public {
        // Create stake
        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        // Advance time to end stake but not past cooldown
        vm.warp(block.timestamp + STAKE_DURATION + 1);

        // Request unstake
        vm.prank(user);
        staking.requestUnstake(0); // stake ID 0

        // Try to unstake before cooldown
        vm.prank(user);
        vm.expectRevert(Staking.CooldownNotPassed.selector);
        staking.unstake(0); // stake ID 0
    }

    function test_RevertWhen_UnstakeWithWrongRecipient() public {
        // Create stake
        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        // Advance time to end stake
        vm.warp(block.timestamp + STAKE_DURATION + 1);

        // Request unstake
        vm.prank(user);
        staking.requestUnstake(0); // stake ID 0

        // Advance time past cooldown
        vm.warp(block.timestamp + COOLDOWN_DURATION + 1);

        // user2 tries to unstake
        vm.prank(user2);
        vm.expectRevert(Staking.MismatchedRecipient.selector);
        staking.unstake(0); // stake ID 0
    }

    function test_RevertWhen_UnstakeNonExistentRequest() public {
        vm.prank(user);
        vm.expectRevert(Staking.UnstakeRequestNotFound.selector);
        staking.unstake(999);
    }

    function test_RevertWhen_RequestUnstakeBeforeStakeEnded() public {
        // Create config without cooldown so requestUnstake calls innerUnstake directly
        StakeConfig memory noCooldownConfig = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: INTEREST_RATE,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: 0, // No cooldown
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(8, noCooldownConfig);

        // Create stake
        vm.prank(user);
        staking.stake(8, user, STAKE_AMOUNT);

        // Try to request unstake before stake duration (advance time but not enough)
        vm.warp(block.timestamp + STAKE_DURATION - 1);

        vm.prank(user);
        vm.expectRevert(Staking.StakeNotEnded.selector);
        staking.requestUnstake(0); // stake ID 0
    }

    function test_Success_UnstakeWithCooldown() public {
        // Create config with zero interest rate to avoid overflow
        StakeConfig memory zeroRateConfig = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: 0, // No interest to avoid overflow
            stakeDuration: 30 days, // Shorter duration
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(6, zeroRateConfig);

        // Create stake
        vm.prank(user);
        staking.stake(6, user, STAKE_AMOUNT);

        uint256 initialBalance = token.balanceOf(user);

        // Advance time to end stake
        vm.warp(block.timestamp + 30 days + 1);

        // Request unstake
        vm.prank(user);
        staking.requestUnstake(0); // stake ID 0

        // Advance time past cooldown
        vm.warp(block.timestamp + COOLDOWN_DURATION + 1);

        // Unstake
        vm.prank(user);
        staking.unstake(0); // stake ID 0

        // Check that tokens were returned (no interest with zero rate)
        assertEq(token.balanceOf(user), initialBalance + STAKE_AMOUNT, "User should receive original tokens back");
        assertEq(staking.stakedAmounts(6, user), 0, "Staked amount should be zero");
    }

    function test_Success_UnstakeWithoutCooldown() public {
        // Create config without cooldown and zero interest rate
        StakeConfig memory noCooldownConfig = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: 0, // No interest to avoid overflow
            stakeDuration: 30 days, // Shorter duration
            cooldownDuration: 0, // No cooldown
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(7, noCooldownConfig);

        // Create stake
        vm.prank(user);
        staking.stake(7, user, STAKE_AMOUNT);

        uint256 initialBalance = token.balanceOf(user);

        // Advance time to end stake
        vm.warp(block.timestamp + 30 days + 1);

        // Request unstake (should unstake immediately)
        vm.prank(user);
        staking.requestUnstake(0); // stake ID 0

        // Check that tokens were returned immediately (no interest with zero rate)
        assertEq(
            token.balanceOf(user), initialBalance + STAKE_AMOUNT, "User should receive original tokens back immediately"
        );
        assertEq(staking.stakedAmounts(7, user), 0, "Staked amount should be zero");
    }

    function test_Success_UnstakeWithoutCooldownWithInterest() public {
        // Create config without cooldown and with interest rate
        StakeConfig memory noCooldownConfig = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: INTEREST_RATE, // 5% interest rate
            stakeDuration: 30 days, // Shorter duration
            cooldownDuration: 0, // No cooldown
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(9, noCooldownConfig);

        // Create stake
        vm.prank(user);
        staking.stake(9, user, STAKE_AMOUNT);

        uint256 initialBalance = token.balanceOf(user);

        // Advance time to end stake (30 days)
        vm.warp(block.timestamp + 30 days + 1);

        // Calculate expected amount with interest
        Stake memory stake = Stake({
            recipient: user,
            configId: 9,
            updatedAt: block.timestamp - 30 days - 1,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp - 30 days - 1,
            principal: STAKE_AMOUNT
        });
        uint256 expectedAmount = staking.calculateAmount(stake);

        // Request unstake (should unstake immediately)
        vm.prank(user);
        staking.requestUnstake(0); // stake ID 0

        // Check that tokens were returned immediately with interest
        assertEq(
            token.balanceOf(user), initialBalance + expectedAmount, "User should receive tokens with interest immediately"
        );
        assertEq(staking.stakedAmounts(9, user), 0, "Staked amount should be zero");
        assertGt(expectedAmount, STAKE_AMOUNT, "Expected amount should be greater than principal due to interest");
    }

    // -------------------------------------------------------------------------
    // Success Cases
    // -------------------------------------------------------------------------

    function test_Success_Stake() public {
        uint256 initialUserBalance = token.balanceOf(user);
        uint256 initialBankBalance = token.balanceOf(bank);

        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        // Check that tokens were transferred to bank
        assertEq(token.balanceOf(bank), initialBankBalance + STAKE_AMOUNT, "Bank should receive staked tokens");
        assertEq(token.balanceOf(user), initialUserBalance - STAKE_AMOUNT, "User should have tokens deducted");
        assertEq(staking.stakedAmounts(CONFIG_ID, user), STAKE_AMOUNT, "Staked amount should be recorded");

        // Check stake data - tuple order: (recipient, configId, updatedAt, amount, startTime, principal)
        (address recipient, uint256 configId,, uint256 amount,, uint256 principal) = staking.stakes(0);
        assertEq(recipient, user, "Stake recipient should be user");
        assertEq(configId, CONFIG_ID, "Stake config ID should match");
        assertEq(amount, STAKE_AMOUNT, "Stake amount should match");
        assertEq(principal, STAKE_AMOUNT, "Stake principal should match");
    }

    function test_Success_StakeOnBehalfOf() public {
        vm.prank(user);
        staking.stake(CONFIG_ID, user2, STAKE_AMOUNT);

        // Check that user2 is the recipient
        (address recipient,,,,,) = staking.stakes(0); // stake ID 0
        assertEq(recipient, user2, "Stake recipient should be user2");
        assertEq(staking.stakedAmounts(CONFIG_ID, user2), STAKE_AMOUNT, "Staked amount should be recorded for user2");
    }

    function test_Success_ConfigCreation() public {
        StakeConfig memory newConfig = StakeConfig({
            bank: bank2,
            manager: manager,
            token: address(token),
            interestRate: INTEREST_RATE,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank2);
        staking.setConfig(10, newConfig);

        // Verify config was created - tuple order: (bank, manager, token, interestRate, stakeDuration, cooldownDuration, maxStake, minStake, isActive, isTopupEnabled, isPublic)
        (address configBank,, address configToken,,,,,,,,) = staking.configs(10);
        assertEq(configBank, bank2, "Config bank should be bank2");
        assertEq(configToken, address(token), "Config token should match");
    }
}
