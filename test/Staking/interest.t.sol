// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {Staking, Stake, StakeConfig} from "../../src/Staking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

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

contract InterestTest is Test {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    Staking public staking;
    MockERC20 public token;

    address public user = address(0x1);
    address public bank = address(0x2);
    address public manager = address(0x3);

    uint256 public constant WAD = 1e18;
    uint256 public constant CONFIG_ID = 1;
    uint256 public constant STAKE_ID = 1;

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

        // Create stake configuration
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

        // Mint tokens to user and bank
        token.mint(user, STAKE_AMOUNT * 10);
        token.mint(bank, STAKE_AMOUNT * 100);

        // Approve staking contract
        vm.prank(user);
        token.approve(address(staking), type(uint256).max);

        vm.prank(bank);
        token.approve(address(staking), type(uint256).max);
    }

    function test_CalculateAmountBasic() public {
        // Create a stake
        Stake memory stake = Stake({
            recipient: user,
            configId: CONFIG_ID,
            updatedAt: block.timestamp,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp
        });

        // Advance time by 1 day
        uint256 timeElapsed = 365 days;
        vm.warp(block.timestamp + timeElapsed);

        uint256 totalAmount = staking.calculateAmount(stake);

        // Expected total amount: amount * (1 + rate)^time
        uint256 expectedTotalAmount = STAKE_AMOUNT.mulWad(uint256(FixedPointMathLib.expWad(int256(INTEREST_RATE))));

        assertEq(totalAmount, expectedTotalAmount, "Total amount calculation incorrect");
        assertGt(totalAmount, STAKE_AMOUNT, "Total amount should be greater than principal");
    }

    function test_CalculateAmountZeroTime() public {
        Stake memory stake = Stake({
            recipient: user,
            configId: CONFIG_ID,
            updatedAt: block.timestamp,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp
        });

        uint256 totalAmount = staking.calculateAmount(stake);
        assertEq(totalAmount, STAKE_AMOUNT, "Total amount should equal principal for zero time elapsed");
    }

    function test_CalculateAmountLargeAmount() public {
        uint256 largeAmount = 1_000_000 * WAD; // 1M tokens

        Stake memory stake = Stake({
            recipient: user,
            configId: CONFIG_ID,
            updatedAt: block.timestamp,
            amount: largeAmount,
            startTime: block.timestamp
        });

        vm.warp(block.timestamp + 30 days);

        uint256 totalAmount = staking.calculateAmount(stake);

        // Should not overflow
        assertGt(totalAmount, largeAmount, "Total amount should be greater than principal for large amounts");
        assertLt(totalAmount, largeAmount * 2, "Total amount should not double for reasonable time periods");
    }

    function test_CalculateAmountHighRate() public {
        // Create config with high interest rate
        uint256 highRate = 0.1e18; // 10% per second
        StakeConfig memory config = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: highRate,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(2, config);

        Stake memory stake = Stake({
            recipient: user,
            configId: 2,
            updatedAt: block.timestamp,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp
        });

        vm.warp(block.timestamp + 1 hours);

        uint256 totalAmount = staking.calculateAmount(stake);
        assertGt(totalAmount, STAKE_AMOUNT, "Total amount should be greater than principal for high rates");
    }

    function test_CalculateAmountZeroRate() public {
        // Create config with zero interest rate
        StakeConfig memory config = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: 0,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(3, config);

        Stake memory stake = Stake({
            recipient: user,
            configId: 3,
            updatedAt: block.timestamp,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp
        });

        vm.warp(block.timestamp + 365 days);

        uint256 totalAmount = staking.calculateAmount(stake);
        assertEq(totalAmount, STAKE_AMOUNT, "Total amount should equal principal for zero rate");
    }

    function test_CalculateAmountExceedsStakeDuration() public {
        Stake memory stake = Stake({
            recipient: user,
            configId: CONFIG_ID,
            updatedAt: block.timestamp,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp
        });

        // Advance time beyond stake duration
        vm.warp(block.timestamp + STAKE_DURATION + 1 days);

        uint256 totalAmount = staking.calculateAmount(stake);

        // Total amount should be capped at stake duration
        uint256 maxTotalAmount = STAKE_AMOUNT.mulWad(uint256(FixedPointMathLib.expWad(int256(INTEREST_RATE))));

        assertEq(totalAmount, maxTotalAmount, "Total amount should be capped at stake duration");
    }

    function test_CalculateAmountInfiniteDuration() public {
        // Create config with infinite duration (0)
        StakeConfig memory config = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: INTEREST_RATE,
            stakeDuration: 0, // Infinite duration
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(4, config);

        Stake memory stake = Stake({
            recipient: user,
            configId: 4,
            updatedAt: block.timestamp,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp
        });

        vm.warp(block.timestamp + 3650 days);

        uint256 totalAmount = staking.calculateAmount(stake);

        // Should calculate total amount for the full time period
        uint256 expectedTotalAmount = STAKE_AMOUNT.mulWad(uint256(FixedPointMathLib.expWad(int256(INTEREST_RATE * 10))));

        assertEq(totalAmount, expectedTotalAmount, "Total amount should be calculated for infinite duration");
    }

    function test_AccureInterest() public {
        Stake memory stake = Stake({
            recipient: user,
            configId: CONFIG_ID,
            updatedAt: block.timestamp,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp
        });

        uint256 start_ = block.timestamp;

        vm.warp(block.timestamp + 7 days);

        Stake memory updatedStake = staking.accured(stake);

        assertEq(updatedStake.updatedAt, block.timestamp, "updatedAt should be updated");
        assertGt(updatedStake.amount, STAKE_AMOUNT, "amount should be increased with interest");
        assertEq(updatedStake.recipient, user, "recipient should remain unchanged");
        assertEq(updatedStake.configId, CONFIG_ID, "configId should remain unchanged");
        assertEq(updatedStake.startTime, start_, "startTime should remain unchanged");

        // Verify the amount matches calculateAmount
        uint256 expectedAmount = staking.calculateAmount(stake);
        assertEq(updatedStake.amount, expectedAmount, "Updated amount should match calculateAmount");
    }

    function test_AccureInterestNoChange() public {
        Stake memory stake = Stake({
            recipient: user,
            configId: CONFIG_ID,
            updatedAt: block.timestamp,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp
        });

        // No time elapsed, so no interest should accrue
        Stake memory updatedStake = staking.accured(stake);

        assertEq(updatedStake.amount, STAKE_AMOUNT, "Amount should remain unchanged when no time has passed");
        assertEq(updatedStake.updatedAt, block.timestamp, "updatedAt should remain unchanged");
    }

    function test_AccureInterestMultipleTimes() public {
        Stake memory stake = Stake({
            recipient: user,
            configId: CONFIG_ID,
            updatedAt: block.timestamp,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp
        });

        // First accrual
        vm.warp(block.timestamp + 1 days);
        stake = staking.accured(stake);
        uint256 firstAmount = stake.amount;

        // Second accrual
        vm.warp(block.timestamp + 1 days);
        stake = staking.accured(stake);
        uint256 secondAmount = stake.amount;

        assertGt(secondAmount, firstAmount, "Second amount should be greater than first");
    }

    function test_CalculateAmountPrecision() public {
        // Test with very small amounts and rates
        uint256 smallAmount = 1e6; // 0.001 tokens
        uint256 smallRate = 1e15; // 0.1% per second

        StakeConfig memory config = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: smallRate,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(5, config);

        Stake memory stake = Stake({
            recipient: user,
            configId: 5,
            updatedAt: block.timestamp,
            amount: smallAmount,
            startTime: block.timestamp
        });

        vm.warp(block.timestamp + 1 hours);

        uint256 totalAmount = staking.calculateAmount(stake);

        // Should handle small amounts without precision loss
        assertGe(totalAmount, smallAmount, "Total amount should be at least the principal for small amounts");
    }

    function test_CalculateAmountFuzz(uint256 amount, uint256 timeElapsed, uint256 rate) public {
        // Bound the inputs to reasonable ranges
        amount = bound(amount, 1e15, 1e24); // 0.001 to 1M tokens
        timeElapsed = bound(timeElapsed, 0, 365 * 5 days);
        rate = bound(rate, 0, 100) * 1e16; // 0% to 10% per year

        // Create config with fuzzed rate
        StakeConfig memory config = StakeConfig({
            bank: bank,
            manager: manager,
            token: address(token),
            interestRate: rate,
            stakeDuration: STAKE_DURATION,
            cooldownDuration: COOLDOWN_DURATION,
            maxStake: MAX_STAKE,
            minStake: MIN_STAKE,
            isActive: true,
            isTopupEnabled: true,
            isPublic: true
        });

        vm.prank(bank);
        staking.setConfig(6, config);

        Stake memory stake = Stake({
            recipient: user,
            configId: 6,
            updatedAt: block.timestamp,
            amount: amount,
            startTime: block.timestamp
        });

        vm.warp(block.timestamp + timeElapsed);
        console.log("timeElapsed", block.timestamp);

        uint256 totalAmount = staking.calculateAmount(stake);

        // Basic invariants
        assertGe(totalAmount, amount, "Total amount should be at least the principal");

        if (rate == 0 || timeElapsed == 0) {
            assertEq(totalAmount, amount, "Total amount should equal principal for zero rate or time");
        } else {
            assertGt(totalAmount, amount, "Total amount should be greater than principal for positive rate and time");
        }

        // Total amount should not exceed reasonable bounds for reasonable rates and time periods
        if (rate <= 0.01e18 && timeElapsed <= 365 days) {
            assertLt(totalAmount, amount * 2, "Total amount should not double for reasonable parameters");
        }
    }

    function test_CalculateAmountEdgeCases() public {
        // Test with maximum uint256 values
        uint256 maxAmount = type(uint256).max;

        Stake memory stake = Stake({
            recipient: user,
            configId: CONFIG_ID,
            updatedAt: block.timestamp,
            amount: maxAmount,
            startTime: block.timestamp
        });

        vm.warp(block.timestamp + 1 seconds);

        // Should not revert due to overflow
        vm.expectRevert(abi.encodeWithSelector(FixedPointMathLib.MulWadFailed.selector));
        staking.calculateAmount(stake);
    }

    function test_CalculateAmountConsistency() public {
        Stake memory stake = Stake({
            recipient: user,
            configId: CONFIG_ID,
            updatedAt: block.timestamp,
            amount: STAKE_AMOUNT,
            startTime: block.timestamp
        });

        vm.warp(block.timestamp + 1 days);

        uint256 totalAmount1 = staking.calculateAmount(stake);
        uint256 totalAmount2 = staking.calculateAmount(stake);

        // Same inputs should produce same outputs
        assertEq(totalAmount1, totalAmount2, "Amount calculation should be deterministic");
    }

    function test_AccureInterestWithExistingInterest() public {
        // Create a stake that already has some interest accrued
        uint256 initialAmount = STAKE_AMOUNT;
        uint256 timeElapsed = 1 days;

        Stake memory stake = Stake({
            recipient: user,
            configId: CONFIG_ID,
            updatedAt: block.timestamp,
            amount: initialAmount,
            startTime: block.timestamp
        });

        vm.warp(block.timestamp + timeElapsed);

        // First accrual
        stake = staking.accured(stake);
        uint256 firstAmount = stake.amount;

        // Advance time further
        vm.warp(block.timestamp + 1 days);

        // Second accrual - should calculate interest on the new total amount
        Stake memory updatedStake = staking.accured(stake);

        assertGt(updatedStake.amount, firstAmount, "Amount should increase with additional interest");
        assertEq(updatedStake.updatedAt, block.timestamp, "updatedAt should be updated");
    }

    function test_IntegrationStakeAndCalculateAmount() public {
        // Test the full integration: stake tokens and then calculate amount
        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        // Get the stake
        (address recipient, uint256 configId, uint256 updatedAt, uint256 amount, uint256 startTime) = staking.stakes(0); // First stake has ID 0

        Stake memory stake = Stake({
            recipient: recipient,
            configId: configId,
            updatedAt: updatedAt,
            amount: amount,
            startTime: startTime
        });

        vm.warp(block.timestamp + 30 days);

        uint256 totalAmount = staking.calculateAmount(stake);

        assertGt(totalAmount, STAKE_AMOUNT, "Total amount should be greater than staked amount");

        // Test accureInterest on the actual stake
        Stake memory updatedStake = staking.accured(stake);
        assertEq(updatedStake.amount, totalAmount, "Updated stake amount should match calculated amount");
    }

    function test_IntegrationTopUpAndCalculateAmount() public {
        // Test top-up functionality with interest calculation
        vm.prank(user);
        staking.stake(CONFIG_ID, user, STAKE_AMOUNT);

        Stake memory preStake_ = getStake(0);
        vm.warp(block.timestamp + 15 days);

        // Top up the stake
        uint256 topUpAmount = 500 * WAD;
        vm.prank(user);
        staking.topUpStake(0, topUpAmount); // Stake ID 0

        uint256 totalAmount = staking.calculateAmount(preStake_);

        Stake memory stake_ = getStake(0);

        assertEq(block.timestamp, stake_.updatedAt, "updatedAt should be updated");

        assertEq(stake_.amount, topUpAmount + totalAmount, "amount should be updated");

        // // The stake should now have the original amount + interest + top-up amount
        // assertGt(stake.amount, STAKE_AMOUNT + topUpAmount, "Stake amount should include interest from top-up");

        // // Calculate what the amount should be after more time
        // vm.warp(block.timestamp + 15 days);
        // uint256 totalAmount = staking.calculateAmount(stake);

        // assertGt(totalAmount, stake.amount, "Total amount should be greater than current stake amount");
    }

    function getStake(uint256 _stakingId) public view returns (Stake memory) {
        (address recipient, uint256 configId, uint256 updatedAt, uint256 amount, uint256 startTime) =
            staking.stakes(_stakingId);

        return Stake({
            recipient: recipient,
            configId: configId,
            updatedAt: updatedAt,
            amount: amount,
            startTime: startTime
        });
    }
}
