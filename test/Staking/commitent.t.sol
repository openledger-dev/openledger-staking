// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {Staking, Stake, StakeConfig} from "../../src/Staking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

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

contract CommitmentTest is Test {
    Staking public staking;
    MockERC20 public token;

    address public user = address(0x1);
    address public user2 = address(0x2);
    address public bank = address(0x3);
    uint256 public manager_sk = uint256(0x9577);

    address public manager;

    // Test configuration
    uint256 public constant WAD = 1e18;
    uint256 public constant STAKE_AMOUNT = 1000 * WAD; // 1000 tokens
    uint256 public constant INTEREST_RATE = 5e16;
    uint256 public constant STAKE_DURATION = 365 days;
    uint256 public constant COOLDOWN_DURATION = 7 days;
    uint256 public constant MAX_STAKE = 10000 * WAD;
    uint256 public constant MIN_STAKE = 100 * WAD;

    function setUp() public {
        manager = vm.addr(manager_sk);

        staking = new Staking();
        token = new MockERC20();

        staking.grantRoles(bank, staking.TRUSTED_BANK());

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
        staking.setConfig(0, config);
    }

    function test_commitment() public {
        uint256 start_ = block.timestamp;
        bytes32 digest = hashTypedData(
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256("Staking"),
                    keccak256("1"),
                    block.chainid,
                    address(staking)
                )
            ),
            keccak256(
                abi.encode(
                    keccak256(
                        "Stake(address recipient,uint256 configId,uint256 amount,uint256 startTime,uint256 nonce)"
                    ),
                    user,
                    0,
                    STAKE_AMOUNT,
                    start_,
                    0
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(manager_sk, digest);

        bytes memory permit = abi.encodePacked(r, s, v);

        vm.prank(user);
        staking.commitStake(permit);

        vm.warp(block.timestamp + STAKE_DURATION);

        vm.prank(user);
        staking.requestUnstakeWithCommitment(
            0,
            0,
            start_,
            0,
            STAKE_AMOUNT
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Signature Replay Tests                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´+°.•*/

    function test_RevertWhen_SignatureReplay() public {
        uint256 start_ = block.timestamp;
        bytes32 digest = hashTypedData(
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256("Staking"),
                    keccak256("1"),
                    block.chainid,
                    address(staking)
                )
            ),
            keccak256(
                abi.encode(
                    keccak256(
                        "Stake(address recipient,uint256 configId,uint256 amount,uint256 startTime,uint256 nonce)"
                    ),
                    user,
                    0,
                    STAKE_AMOUNT,
                    start_,
                    0
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(manager_sk, digest);
        bytes memory permit = abi.encodePacked(r, s, v);

        // First commitment should succeed
        vm.prank(user);
        staking.commitStake(permit);

        // Second commitment with same signature should fail
        vm.prank(user);
        vm.expectRevert(Staking.SignatureReplayed.selector);
        staking.commitStake(permit);
    }

    function test_RevertWhen_SignatureReplayDifferentUser() public {
        uint256 start_ = block.timestamp;
        bytes32 digest = hashTypedData(
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256("Staking"),
                    keccak256("1"),
                    block.chainid,
                    address(staking)
                )
            ),
            keccak256(
                abi.encode(
                    keccak256(
                        "Stake(address recipient,uint256 configId,uint256 amount,uint256 startTime,uint256 nonce)"
                    ),
                    user,
                    0,
                    STAKE_AMOUNT,
                    start_,
                    0
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(manager_sk, digest);
        bytes memory permit = abi.encodePacked(r, s, v);

        // First commitment by user
        vm.prank(user);
        staking.commitStake(permit);

        // Second commitment by different user with same signature should fail
        vm.prank(user2);
        vm.expectRevert(Staking.SignatureReplayed.selector);
        staking.commitStake(permit);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                Invalid Message Sender Tests                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´+°.•*/

    function test_RevertWhen_RequestUnstakeWithCommitmentInvalidSender() public {
        uint256 start_ = block.timestamp;
        bytes32 digest = hashTypedData(
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256("Staking"),
                    keccak256("1"),
                    block.chainid,
                    address(staking)
                )
            ),
            keccak256(
                abi.encode(
                    keccak256(
                        "Stake(address recipient,uint256 configId,uint256 amount,uint256 startTime,uint256 nonce)"
                    ),
                    user,
                    0,
                    STAKE_AMOUNT,
                    start_,
                    0
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(manager_sk, digest);
        bytes memory permit = abi.encodePacked(r, s, v);

        // Create commitment
        vm.prank(user);
        staking.commitStake(permit);

        vm.warp(block.timestamp + STAKE_DURATION);

        // Try to request unstake with commitment using wrong sender
        vm.prank(user2);
        vm.expectRevert(Ownable.Unauthorized.selector);
        staking.requestUnstakeWithCommitment(
            0,
            0,
            start_,
            0,
            STAKE_AMOUNT
        );
    }

    function test_RevertWhen_RequestUnstakeWithCommitmentNonExistentCommitment() public {
        // Try to request unstake with commitment that doesn't exist
        vm.prank(user);
        vm.expectRevert(Staking.StakeNotFound.selector);
        staking.requestUnstakeWithCommitment(
            999, // Non-existent stake ID
            0,
            block.timestamp,
            0,
            STAKE_AMOUNT
        );
    }

    function test_RevertWhen_RequestUnstakeWithCommitmentInvalidSignature() public {
        uint256 start_ = block.timestamp;
        bytes32 digest = hashTypedData(
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256("Staking"),
                    keccak256("1"),
                    block.chainid,
                    address(staking)
                )
            ),
            keccak256(
                abi.encode(
                    keccak256(
                        "Stake(address recipient,uint256 configId,uint256 amount,uint256 startTime,uint256 nonce)"
                    ),
                    user,
                    0,
                    STAKE_AMOUNT,
                    start_,
                    0
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(manager_sk, digest);
        bytes memory permit = abi.encodePacked(r, s, v);

        // Create commitment
        vm.prank(user);
        staking.commitStake(permit);

        vm.warp(block.timestamp + STAKE_DURATION);

        // Try to request unstake with commitment using wrong signature (different nonce)
        vm.prank(user);
        vm.expectRevert(Ownable.Unauthorized.selector);
        staking.requestUnstakeWithCommitment(
            0,
            0,
            start_,
            1, // Different nonce
            STAKE_AMOUNT
        );
    }

    function test_Success_RequestUnstakeWithCommitment() public {
        uint256 start_ = block.timestamp;
        bytes32 digest = hashTypedData(
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256("Staking"),
                    keccak256("1"),
                    block.chainid,
                    address(staking)
                )
            ),
            keccak256(
                abi.encode(
                    keccak256(
                        "Stake(address recipient,uint256 configId,uint256 amount,uint256 startTime,uint256 nonce)"
                    ),
                    user,
                    0,
                    STAKE_AMOUNT,
                    start_,
                    0
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(manager_sk, digest);
        bytes memory permit = abi.encodePacked(r, s, v);

        // Create commitment
        vm.prank(user);
        staking.commitStake(permit);

        // Verify commitment was stored
        bytes memory storedCommitment = staking.stakeCommitments(0);
        assertEq(storedCommitment, permit, "Commitment should be stored correctly");

        vm.warp(block.timestamp + STAKE_DURATION);

        // Request unstake with commitment
        vm.prank(user);
        staking.requestUnstakeWithCommitment(
            0,
            0,
            start_,
            0,
            STAKE_AMOUNT
        );

        // Verify commitment was deleted
        bytes memory deletedCommitment = staking.stakeCommitments(0);
        assertEq(deletedCommitment.length, 0, "Commitment should be deleted after use");
    }


    function hashTypedData(bytes32 dominSeperator, bytes32 structHash) public pure returns (bytes32 digest) {
                /// @solidity memory-safe-assembly
        assembly {
            // Compute the digest.
            mstore(0x00, 0x1901000000000000) // Store "\x19\x01".
            mstore(0x1a, dominSeperator) // Store the domain separator.
            mstore(0x3a, structHash) // Store the struct hash.
            digest := keccak256(0x18, 0x42)
            // Restore the part of the free memory slot that was overwritten.
            mstore(0x3a, 0)
        }
    }
}