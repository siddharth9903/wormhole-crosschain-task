# Cross-Chain Token Minting with Wormhole

This project demonstrates cross-chain token minting using Wormhole's relayer network. Users can sign a message on Chain A (Goerli) to initiate a process that mints tokens after verification through Chain B (Mumbai).

## Features

- Cross-chain message passing using Wormhole
- Message signing and verification
- Token minting with limits (20 mints maximum)
- Automated testing with Foundry
- Complete deployment scripts for both chains

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/)

## Project Setup

1. Clone and install dependencies:
```bash
# Clone the repository
git clone <repository-url>
cd cross-chain-tokens

# Install Foundry dependencies
forge install wormhole-foundation/wormhole-solidity-sdk --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```


## Testing

Run the test suite:
```bash
# Run all tests
forge test -vvv

# Run specific test
forge test --match-test testCrossChainMinting -vvv

# Run tests with gas reporting
forge test --gas-report
```

## Architecture

See [docs/wormhole-flow.md](./docs/wormhole-flow.md) for a detailed sequence diagram of the cross-chain communication flow.

## Network Details
https://wormhole.com/docs/build/reference/contract-addresses/