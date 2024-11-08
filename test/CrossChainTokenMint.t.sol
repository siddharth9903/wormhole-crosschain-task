// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";
import { ChainAContract } from "../src/ChainAContract.sol";
import { ChainBContract } from "../src/ChainBContract.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract CrossChainTokenMint is WormholeRelayerBasicTest {
    ChainAContract public chainAContract;
    ChainBContract public chainBContract;

    uint256 constant TOKENS_PER_MINT = 100 * 10 ** 18;

    function setUpSource() public override {
        chainAContract = new ChainAContract(address(relayerSource), targetChain);
    }

    function setUpTarget() public override {
        chainBContract = new ChainBContract(address(relayerTarget), address(chainAContract), sourceChain);
    }

    function signMessage(uint256 privateKey, string memory message) internal pure returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(bytes(message).length), message)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function performCrossChainMint(address user, bytes memory signature) internal {
        // Get quote for cross-chain message
        uint256 cost = chainAContract.quoteCrossChainMessage();

        // Submit signature and initiate cross-chain process
        vm.recordLogs();
        chainAContract.submitSignature{ value: cost }(address(chainBContract), signature);

        // Deliver message from Chain A to Chain B
        performDelivery();

        // Switch to target chain for Chain B processing
        vm.selectFork(targetFork);

        // Deliver return message from Chain B to Chain A
        performDelivery();

        // Switch back to source chain to verify minting
        vm.selectFork(sourceFork);
    }

    function testCrossChainMinting() public {
        // Test user setup with known private key
        uint256 privateKey = 0x1234;
        address user = vm.addr(privateKey);
        vm.deal(user, 100 ether);

        // Fund Chain B for return message fees
        vm.selectFork(targetFork);
        vm.deal(address(chainBContract), 1 ether);
        vm.selectFork(sourceFork);

        vm.startPrank(user);

        // Create and sign message
        string memory message = "Ethereum Signed Message For Airdrop on Chain B";
        bytes memory signature = signMessage(privateKey, message);

        // Perform cross-chain minting
        performCrossChainMint(user, signature);

        // Verify minting
        assertEq(chainAContract.balanceOf(user), TOKENS_PER_MINT);
        assertEq(chainAContract.mintCount(), 1);
        assertTrue(chainAContract.hasMinted(user));

        vm.stopPrank();
    }

    function testMultipleUsers() public {
        // Fund Chain B for return message fees
        vm.selectFork(targetFork);
        vm.deal(address(chainBContract), 100 ether);
        vm.selectFork(sourceFork);

        for (uint256 i = 1; i <= 20; i++) {
            // Create user address with known private key
            uint256 privateKey = i;
            address user = vm.addr(privateKey);
            vm.deal(user, 100 ether);
            vm.startPrank(user);

            // Sign message
            string memory message = "Ethereum Signed Message For Airdrop on Chain B";
            bytes memory signature = signMessage(privateKey, message);

            // Perform cross-chain minting
            performCrossChainMint(user, signature);

            // Verify
            assertEq(chainAContract.balanceOf(user), TOKENS_PER_MINT);
            assertTrue(chainAContract.hasMinted(user));

            vm.stopPrank();
        }

        // Verify total supply and mint count
        assertEq(chainAContract.mintCount(), 20);
        assertEq(chainAContract.totalSupply(), TOKENS_PER_MINT * 20);
    }

    function testCannotMintMoreThanMaximum() public {
        // Fund Chain B for return message fees
        vm.selectFork(targetFork);
        vm.deal(address(chainBContract), 100 ether);
        vm.selectFork(sourceFork);

        // Try to mint 21 times (should fail on the 21st)
        for (uint256 i = 1; i <= 21; i++) {
            uint256 privateKey = i;
            address user = vm.addr(privateKey);
            vm.deal(user, 100 ether);
            vm.startPrank(user);

            string memory message = "Ethereum Signed Message For Airdrop on Chain B";
            bytes memory signature = signMessage(privateKey, message);

            uint256 cost = chainAContract.quoteCrossChainMessage();

            if (i <= 20) {
                performCrossChainMint(user, signature);
            } else {
                vm.expectRevert("Max mints reached");
                chainAContract.submitSignature{ value: cost }(address(chainBContract), signature);
            }

            vm.stopPrank();
        }
    }
}
