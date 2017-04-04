# Legal and smart contracts framework to implement Employee Stock Options Plan

## What is ESOP and why we do it?

## Actors and Their Lifecycles

**Admin**
**CEO**
**Employee**

**Option Pools**


## Neufund ESOP Algorithm

Simulations


## Smart Contracts

### Option Conversion Event

## Legal Papers

## User Interface

## Development
solc 0.4.10
install binary packages cpp solc from solc repo http://solidity.readthedocs.io/en/develop/installing-solidity.html to use with dapple
upgrade truffle by modifying package.js of truffle and putting right solc version like
```
cd /usr/lib/node_modules/truffle
atom package.js <- change solc version
npm update
```

### Running unit (solidity) tests
Solidity tests are run with dapple.

### Running integration (js) tests

RoT.at(RoT.address).ESOPAddress()
ESOP.at(ESOP.address).rootOfTrust()

### setting up dev chain on parity and get some eth
parity --chain dev --jsonrpc-port 8444 ui
https://github.com/paritytech/parity/wiki/Private-development-chain

### Steps to reproduce and verify bytecode deployed on mainnet
