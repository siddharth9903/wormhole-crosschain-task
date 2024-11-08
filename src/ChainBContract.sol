// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IWormholeRelayer } from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import { IWormholeReceiver } from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";

contract ChainBContract is IWormholeReceiver {
    uint256 constant GAS_LIMIT = 200_000;

    IWormholeRelayer public immutable wormholeRelayer;
    uint16 public immutable sourceChain;
    address public immutable chainAContract;

    mapping(bytes32 => bool) public processedDeliveryHashes;

    event MessageReceived(address indexed user);
    event TokenMintInitiated(address indexed user);

    constructor(address _wormholeRelayer, address _chainAContract, uint16 _sourceChain) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        chainAContract = _chainAContract;
        sourceChain = _sourceChain;
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 _sourceChain,
        bytes32 deliveryHash
    ) public payable override {
        require(msg.sender == address(wormholeRelayer), "Only relayer allowed");
        require(_sourceChain == sourceChain, "Wrong source chain");
        require(sourceAddress == bytes32(uint256(uint160(chainAContract))), "Wrong source contract");
        require(!processedDeliveryHashes[deliveryHash], "Message already processed");

        address user = abi.decode(payload, (address));

        // Get delivery price quote for return message
        (uint256 deliveryPrice,) = wormholeRelayer.quoteEVMDeliveryPrice(sourceChain, 0, GAS_LIMIT);

        // Send message back to Chain A to initiate minting
        wormholeRelayer.sendPayloadToEvm{ value: deliveryPrice }(
            sourceChain,
            chainAContract,
            abi.encode(user),
            0, // no receiver value
            GAS_LIMIT
        );

        processedDeliveryHashes[deliveryHash] = true;
        emit MessageReceived(user);
        emit TokenMintInitiated(user);
    }

    // Function to receive ETH for relayer fees
    receive() external payable { }
}
