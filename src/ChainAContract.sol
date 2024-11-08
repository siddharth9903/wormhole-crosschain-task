// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IWormholeRelayer } from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import { IWormholeReceiver } from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ChainAContract is ERC20, Ownable, IWormholeReceiver {
    uint256 constant GAS_LIMIT = 200_000;
    uint256 public constant TOKENS_PER_MINT = 100 * 10 ** 18; // 100 tokens
    uint256 public constant MAX_MINTS = 20;

    IWormholeRelayer public immutable wormholeRelayer;
    uint16 public immutable targetChain;

    uint256 public mintCount;
    mapping(address => bool) public hasMinted;
    mapping(bytes32 => bool) public processedDeliveryHashes;

    event SignatureSubmitted(address indexed user, bytes signature);
    event CrossChainMessageSent(uint16 targetChain, address targetAddress);
    event TokensMinted(address indexed user);

    constructor(address _wormholeRelayer, uint16 _targetChain) ERC20("ABC Token", "ABC") Ownable(msg.sender) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        targetChain = _targetChain;
    }

    function quoteCrossChainMessage() public view returns (uint256 cost) {
        (cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
    }

    function submitSignature(address targetAddress, bytes memory signature) external payable {
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
            targetAddress,
            abi.encode(msg.sender),
            0, // no receiver value
            GAS_LIMIT
        );

        emit SignatureSubmitted(msg.sender, signature);
        emit CrossChainMessageSent(targetChain, targetAddress);
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override {
        require(msg.sender == address(wormholeRelayer), "Only relayer allowed");
        require(!processedDeliveryHashes[deliveryHash], "Message already processed");
        require(sourceChain == targetChain, "Invalid source chain");

        address user = abi.decode(payload, (address));
        require(!hasMinted[user], "Already minted");
        require(mintCount < MAX_MINTS, "Max mints reached");

        // Mint tokens
        _mint(user, TOKENS_PER_MINT);
        hasMinted[user] = true;
        mintCount++;

        processedDeliveryHashes[deliveryHash] = true;
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
