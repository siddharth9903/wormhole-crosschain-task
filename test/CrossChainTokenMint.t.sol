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
    address owner;

    function setUpSource() public virtual override {
        // Create a deterministic address for owner using vm.addr(1)
        owner = vm.addr(1);
        vm.deal(owner, 100 ether);

        // Deploy Chain A contract as owner
        vm.prank(owner);
        chainAContract = new ChainAContract(address(relayerSource), targetChain);
    }

    function setUpTarget() public virtual override {
        // Deploy Chain B contract
        vm.prank(owner);
        chainBContract = new ChainBContract(address(relayerTarget), address(chainAContract), sourceChain);

        // Switch back to source fork to set Chain B address
        vm.selectFork(sourceFork);
        vm.prank(owner);
        chainAContract.setChainBContract(address(chainBContract));

        // Fund Chain B with ETH for return messages
        vm.selectFork(targetFork);
        vm.deal(address(chainBContract), 100 ether);
    }

    function testCannotsetChainBContractTwice() public {
        vm.selectFork(sourceFork);
        vm.prank(owner);
        vm.expectRevert(ChainAContract.ChainBContractAlreadySet.selector);
        chainAContract.setChainBContract(address(0x123));
    }

    function testCannotsetChainBContractToZeroAddress() public {
        // Deploy new Chain A contract for this test
        vm.selectFork(sourceFork);
        vm.startPrank(owner);
        ChainAContract newChainA = new ChainAContract(address(relayerSource), targetChain);
        vm.expectRevert(ChainAContract.InvalidChainBContractAddress.selector);
        newChainA.setChainBContract(address(0));
        vm.stopPrank();
    }

    function testOnlyOwnerCansetChainBContract() public {
        vm.selectFork(sourceFork);

        // Deploy new Chain A contract as owner
        vm.prank(owner);
        ChainAContract newChainA = new ChainAContract(address(relayerSource), targetChain);

        // Try to set ChainB as non-owner
        address nonOwner = vm.addr(2);
        vm.prank(nonOwner);
        vm.expectRevert();
        newChainA.setChainBContract(address(chainBContract));
    }

    function testRecoverETH() public {
        vm.selectFork(targetFork);
        vm.deal(address(chainBContract), 5 ether);

        // Test as non-owner
        vm.prank(vm.addr(2));
        vm.expectRevert();
        chainBContract.recoverETH();

        // Test as owner
        uint256 initialBalance = owner.balance;
        vm.prank(owner);
        chainBContract.recoverETH();
        assertEq(owner.balance - initialBalance, 5 ether);
    }

    function signMessage(uint256 privateKey, string memory message) internal pure returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(bytes(message).length), message)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function performCrossChainMint(address user, bytes memory signature) internal {
        vm.recordLogs();
        uint256 cost = chainAContract.quoteCrossChainMessage();
        chainAContract.submitSignature{ value: cost }(signature);
        performDelivery();
        vm.selectFork(targetFork);
        performDelivery();
        vm.selectFork(sourceFork);
    }

    function testBasicSetup() public {
        assertEq(address(chainAContract.wormholeRelayer()), address(relayerSource));
        assertEq(chainAContract.targetChain(), targetChain);
        assertEq(chainAContract.owner(), owner);
        assertTrue(chainAContract.isChainBContractSet());
        assertEq(chainAContract.chainBContract(), address(chainBContract));

        // Test Chain B setup
        vm.selectFork(targetFork);
        assertEq(address(chainBContract.wormholeRelayer()), address(relayerTarget));
        assertEq(chainBContract.sourceChain(), sourceChain);
        assertEq(chainBContract.chainAContract(), address(chainAContract));
        assertEq(chainBContract.owner(), owner);
    }

    function testInitialSetup() public {
        assertEq(address(chainAContract.wormholeRelayer()), address(relayerSource));
        assertEq(chainAContract.targetChain(), targetChain);
        assertEq(chainAContract.owner(), owner);
        assertTrue(chainAContract.isChainBContractSet());
        assertEq(chainAContract.chainBContract(), address(chainBContract));
    }

    // Test signature verification
    function testInvalidSignature() public {
        address user = vm.addr(1);
        vm.deal(user, 100 ether);
        vm.startPrank(user);

        string memory message = "Ethereum Signed Message For Airdrop on Chain B";
        bytes memory signature = signMessage(2, message); // Wrong private key

        uint256 cost = chainAContract.quoteCrossChainMessage();
        vm.expectRevert("Invalid signature");
        chainAContract.submitSignature{ value: cost }(signature);
    }

    // Test payment handling
    function testInsufficientPayment() public {
        address user = vm.addr(1);
        vm.deal(user, 100 ether);
        vm.startPrank(user);

        string memory message = "Ethereum Signed Message For Airdrop on Chain B";
        bytes memory signature = signMessage(1, message);

        uint256 cost = chainAContract.quoteCrossChainMessage();
        vm.expectRevert("Insufficient payment for message delivery");
        chainAContract.submitSignature{ value: cost - 1 }(signature);
    }

    // Test duplicate minting prevention
    function testCannotMintTwice() public {
        address user = vm.addr(1);
        vm.deal(user, 100 ether);
        vm.startPrank(user);

        // Fund Chain B
        vm.selectFork(targetFork);
        vm.deal(address(chainBContract), 1 ether);
        vm.selectFork(sourceFork);

        string memory message = "Ethereum Signed Message For Airdrop on Chain B";
        bytes memory signature = signMessage(1, message);

        // First mint
        performCrossChainMint(user, signature);

        // Try second mint
        uint256 cost = chainAContract.quoteCrossChainMessage();
        vm.expectRevert("Already minted");
        chainAContract.submitSignature{ value: cost }(signature);
    }

    function testCrossChainMinting() public {
        vm.selectFork(sourceFork);
        address user = vm.addr(2);
        vm.deal(user, 100 ether);

        // Ensure Chain B has funds
        vm.selectFork(targetFork);
        vm.deal(address(chainBContract), 1 ether);
        vm.selectFork(sourceFork);

        vm.startPrank(user);

        // Create and sign message
        string memory message = "Ethereum Signed Message For Airdrop on Chain B";
        bytes memory signature = signMessage(2, message);

        // Get quote and submit
        uint256 cost = chainAContract.quoteCrossChainMessage();

        // Record logs and submit
        vm.recordLogs();
        chainAContract.submitSignature{ value: cost }(signature);

        // Deliver to Chain B
        performDelivery();

        // Switch to Chain B and process
        vm.selectFork(targetFork);
        performDelivery();

        // Switch back to Chain A and verify
        vm.selectFork(sourceFork);

        // Verify minting results
        assertEq(chainAContract.balanceOf(user), TOKENS_PER_MINT);
        assertEq(chainAContract.mintCount(), 1);
        assertTrue(chainAContract.hasMinted(user));

        vm.stopPrank();
    }

    function testMultipleUsers() public {
        // Fund Chain B first
        vm.selectFork(targetFork);
        vm.deal(address(chainBContract), 100 ether);
        vm.selectFork(sourceFork);

        // Test 20 different users
        for (uint256 i = 1; i <= 20; i++) {
            // Each user gets a different private key/address
            address user = vm.addr(i + 100); // Starting from 101 to avoid conflicts
            vm.deal(user, 100 ether);

            vm.startPrank(user);

            // Create and sign message
            string memory message = "Ethereum Signed Message For Airdrop on Chain B";
            bytes memory signature = signMessage(i + 100, message);

            // Get quote and submit
            uint256 cost = chainAContract.quoteCrossChainMessage();

            // Record logs and submit
            vm.recordLogs();
            chainAContract.submitSignature{ value: cost }(signature);

            // Process the cross-chain messages
            performDelivery();
            vm.selectFork(targetFork);
            performDelivery();
            vm.selectFork(sourceFork);

            // Verify for each user
            assertEq(chainAContract.balanceOf(user), TOKENS_PER_MINT);
            assertTrue(chainAContract.hasMinted(user));

            vm.stopPrank();
        }

        // Verify final state
        assertEq(chainAContract.mintCount(), 20);
        assertEq(chainAContract.totalSupply(), TOKENS_PER_MINT * 20);
    }

    function testCannotMintMoreThanMaximum() public {
        // Fund Chain B first
        vm.selectFork(targetFork);
        vm.deal(address(chainBContract), 100 ether);
        vm.selectFork(sourceFork);

        // First mint 20 times successfully
        for (uint256 i = 1; i <= 20; i++) {
            address user = vm.addr(i + 200); // Starting from 201 to avoid conflicts
            vm.deal(user, 100 ether);

            vm.startPrank(user);

            string memory message = "Ethereum Signed Message For Airdrop on Chain B";
            bytes memory signature = signMessage(i + 200, message);

            uint256 cost = chainAContract.quoteCrossChainMessage();

            vm.recordLogs();
            chainAContract.submitSignature{ value: cost }(signature);

            performDelivery();
            vm.selectFork(targetFork);
            performDelivery();
            vm.selectFork(sourceFork);

            vm.stopPrank();
        }

        // Try to mint the 21st time - should fail
        address extraUser = vm.addr(221);
        vm.deal(extraUser, 100 ether);

        vm.startPrank(extraUser);

        string memory message = "Ethereum Signed Message For Airdrop on Chain B";
        bytes memory signature = signMessage(221, message);

        uint256 cost = chainAContract.quoteCrossChainMessage();

        // This should revert with "Max mints reached"
        vm.expectRevert("Max mints reached");
        chainAContract.submitSignature{ value: cost }(signature);

        vm.stopPrank();
    }
}
