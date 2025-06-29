// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "solady/utils/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

/// @title  SigDispersal
/// @author Clique (@Clique2046)
/// @author Alan (@alannotnerd)
contract SigDispersal is OwnableRoles {
    using SafeERC20 for IERC20;

    // address signing the claims
    address public signer;
    // vault address
    address public vault;
    // whether the airdrop is active
    bool public active = false;

    address public token;

    mapping(bytes32 => mapping(address => uint256)) public claimed;
    mapping(bytes32 => bool) public batchEnabled;

    // errors
    error AlreadyClaimed();
    error InvalidSignature();
    error NotActive();
    error ZeroAddress();

    event AirdropClaimed(bytes32 indexed batch, address indexed account, uint256 amount);
    event VaultSet(address indexed vault);
    event TokenSet(address indexed token);
    event BatchEnabled(bytes32 indexed root, bool enabled);

    uint256 public constant PROJECT_ADMIN = _ROLE_0;

    /// @notice Construct a new Claim contract
    /// @param _signer address that can sign messages
    /// @param _projectAdmin address that can set the signer and claim root
    constructor(address _signer, address _projectAdmin, address _vault) {
        signer = _signer;
        vault = _vault;
        _initializeOwner(msg.sender);
        _setRoles(_projectAdmin, PROJECT_ADMIN);
    }

    /// @notice Modifier to check if the airdrop is active
    modifier whenActive() {
        if (!active) revert NotActive();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set the signer
    /// @param _signer address that can sign messages
    function setSigner(address _signer) external onlyRoles(PROJECT_ADMIN) {
        signer = _signer;
    }

    /// @notice Set the vault
    /// @param _vault address of the vault
    function setVault(address _vault) external onlyRoles(PROJECT_ADMIN) {
        vault = _vault;
        emit VaultSet(_vault);
    }

    /// @notice Toggle the active state
    function toggleActive() external onlyRoles(PROJECT_ADMIN) {
        active = !active;
    }

    /// @notice Set the token
    /// @param _token address of the token
    function setToken(address _token) external onlyRoles(PROJECT_ADMIN) {
        token = _token;
        emit TokenSet(_token);
    }

    /// @notice Set the batch enabled state
    /// @param _root root of the batch
    /// @param _enabled whether the batch is enabled
    function setBatchEnabled(bytes32 _root, bool _enabled) external onlyRoles(PROJECT_ADMIN) {
        batchEnabled[_root] = _enabled;
        emit BatchEnabled(_root, _enabled);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   EXTERNAL FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Claim airdrop tokens. Checks for both merkle proof
    //          and signature validation
    /// @param _signature signature of the claim
    /// @param _batch batch to check
    /// @param _amount amount of tokens to claim
    /// @param _onBehalfOf address to claim on behalf of
    function claim(bytes calldata _signature, bytes32 _batch, uint256 _amount, address _onBehalfOf)
        external
        payable
        whenActive
    {
        address _signer = signer;

        // if the signer is not set, skip signature check
        _signatureCheck(_amount, _onBehalfOf, _signature, _signer, _batch);

        uint256 _claimHeight = claimed[_batch][_onBehalfOf];
        if (_claimHeight > 0) {
            revert AlreadyClaimed();
        }
        claimed[_batch][_onBehalfOf] = block.number;

        IERC20(token).safeTransferFrom(vault, _onBehalfOf, _amount);

        emit AirdropClaimed(_batch, _onBehalfOf, _amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       PRIVATE FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Internal function to check the signature
    /// @param _amount amount of tokens to claim
    /// @param _onBehalfOf address to claim on behalf of
    /// @param _signature signature of the claim
    /// @param _signer signer to check
    /// @param _batch batch to check
    function _signatureCheck(
        uint256 _amount,
        address _onBehalfOf,
        bytes calldata _signature,
        address _signer,
        bytes32 _batch
    ) internal view {
        if (_signature.length == 0) revert InvalidSignature();

        bytes32 messageHash = keccak256(abi.encodePacked(_onBehalfOf, _amount, _batch, address(this), block.chainid));
        bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(messageHash);
        address recoveredSigner = ECDSA.recoverCalldata(prefixedHash, _signature);

        if (recoveredSigner != _signer) revert InvalidSignature();
    }
}
