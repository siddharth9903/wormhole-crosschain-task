// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IWormholeRelayer } from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import { IWormholeReceiver } from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ChainAContract is ERC20, Ownable, ReentrancyGuard, IWormholeReceiver {
    uint256 constant GAS_LIMIT = 200_000;
    uint256 public constant TOKENS_PER_MINT = 100 * 10 ** 18; // 100 tokens
    uint256 public constant MAX_MINTS = 20;

    IWormholeRelayer public immutable wormholeRelayer;
    uint16 public immutable targetChain;

    address public chainBContract;
    bool public isChainBContractSet;

    uint256 public mintCount;
    mapping(address => bool) public hasMinted;
    mapping(bytes32 => bool) public processedDeliveryHashes;

    event SignatureSubmitted(address indexed user, bytes signature);
    event CrossChainMessageSent(uint16 targetChain, address targetAddress);
    event TokensMinted(address indexed user);
    event ChainBContractSet(address chainBContract);

    error UnauthorizedChainBContractSet();
    error ChainBContractAlreadySet();
    error ChainBContractNotSet();
    error InvalidChainBContractAddress();

    constructor(address _wormholeRelayer, uint16 _targetChain) ERC20("ABC Token", "ABC") Ownable(msg.sender) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        targetChain = _targetChain;
    }

    function setChainBContract(address _chainBContract) external onlyOwner {
        if (isChainBContractSet) revert ChainBContractAlreadySet();
        if (_chainBContract == address(0)) revert InvalidChainBContractAddress();

        isChainBContractSet = true;
        chainBContract = _chainBContract;

        emit ChainBContractSet(_chainBContract);
    }

    function quoteCrossChainMessage() public view returns (uint256 cost) {
        (cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
    }

    function submitSignature(bytes memory signature) external payable nonReentrant {
        if (!isChainBContractSet) revert ChainBContractNotSet();
        require(mintCount < MAX_MINTS, "Max mints reached");
        require(!hasMinted[msg.sender], "Already minted");

        // Verify signature
        string memory message = "Ethereum Signed Message For Airdrop on Chain B";
        bytes32 messageHash = getEthSignedMessageHash(message);
        address signer = recoverSigner(messageHash, signature);

        require(signer == msg.sender, "Invalid signature");

        // Quote and verify payment
        uint256 cost = quoteCrossChainMessage();
        require(msg.value >= cost, "Insufficient payment for message delivery");

        // Send cross-chain message
        wormholeRelayer.sendPayloadToEvm{ value: cost }(
            targetChain,
            chainBContract,
            abi.encode(msg.sender),
            0, // no receiver value
            GAS_LIMIT
        );

        emit SignatureSubmitted(msg.sender, signature);
        emit CrossChainMessageSent(targetChain, chainBContract);
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override nonReentrant {
        if (!isChainBContractSet) revert ChainBContractNotSet();

        // Initial validations
        require(msg.sender == address(wormholeRelayer), "Only relayer allowed");
        require(!processedDeliveryHashes[deliveryHash], "Message already processed");
        require(sourceChain == targetChain, "Invalid source chain");
        require(sourceAddress == bytes32(uint256(uint160(chainBContract))), "Invalid source contract");

        // Decode and validate payload
        address user = abi.decode(payload, (address));
        require(user != address(0), "Invalid user address");
        require(!hasMinted[user], "Already minted");
        require(mintCount < MAX_MINTS, "Max mints reached");

        processedDeliveryHashes[deliveryHash] = true;
        hasMinted[user] = true;
        mintCount++;

        _mint(user, TOKENS_PER_MINT);

        emit TokensMinted(user);
    }

    function getMessageHash(string memory message) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(message));
    }

    function getEthSignedMessageHash(string memory message) public pure returns (bytes32) {
        // Length of message needs to be part of the signed data
        string memory prefix = string.concat("\x19Ethereum Signed Message:\n", Strings.toString(bytes(message).length));
        return keccak256(abi.encodePacked(prefix, message));
    }

    function recoverSigner(bytes32 messageHash, bytes memory signature) public pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "Invalid signature recovery value");
        return ecrecover(messageHash, v, r, s);
    }
}
