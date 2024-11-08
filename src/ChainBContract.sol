// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IWormholeRelayer } from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import { IWormholeReceiver } from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ChainBContract is Ownable, ReentrancyGuard, IWormholeReceiver {
    uint256 constant GAS_LIMIT = 200_000;

    IWormholeRelayer public immutable wormholeRelayer;
    uint16 public immutable sourceChain;
    address public immutable chainAContract;

    mapping(bytes32 => bool) public processedDeliveryHashes;

    event MessageReceived(address indexed user);
    event TokenMintInitiated(address indexed user);

    error InsufficientBalance(uint256 required, uint256 available);

    constructor(address _wormholeRelayer, address _chainAContract, uint16 _sourceChain) Ownable(msg.sender) {
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
    ) public payable override nonReentrant {
        require(msg.sender == address(wormholeRelayer), "Only relayer allowed");
        require(_sourceChain == sourceChain, "Wrong source chain");
        require(sourceAddress == bytes32(uint256(uint160(chainAContract))), "Wrong source contract");
        require(!processedDeliveryHashes[deliveryHash], "Message already processed");

        address user = abi.decode(payload, (address));
        require(user != address(0), "Invalid user address");

        // Get delivery price and check balance
        (uint256 deliveryPrice,) = wormholeRelayer.quoteEVMDeliveryPrice(sourceChain, 0, GAS_LIMIT);

        if (address(this).balance < deliveryPrice) {
            revert InsufficientBalance(deliveryPrice, address(this).balance);
        }

        processedDeliveryHashes[deliveryHash] = true;
        emit MessageReceived(user);

        wormholeRelayer.sendPayloadToEvm{ value: deliveryPrice }(
            sourceChain,
            chainAContract,
            abi.encode(user),
            0, // no receiver value
            GAS_LIMIT
        );
        emit TokenMintInitiated(user);
    }

    function recoverETH() external onlyOwner {
        (bool success,) = owner().call{ value: address(this).balance }("");
        require(success, "ETH recovery failed");
    }

    // Function to receive ETH for relayer fees
    receive() external payable { }
}
