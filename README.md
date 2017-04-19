# Legal and smart contracts framework to implement Employee Stock Options Plan

## What is ESOP and why we do it?

## Actors and Their Lifecycles

**Admin**
**company**
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

running testrpc with lower block gas limit ~ mainnet limit
`testrpc --gasLimit=4000000  -i=192837991`
`truffle deploy --network deployment`

### setting up dev chain on parity and get some eth
parity --chain dev --jsonrpc-port 8444 ui
https://github.com/paritytech/parity/wiki/Private-development-chain

### Steps to reproduce and verify bytecode deployed on mainnet


--------------------
fineprints:
I hereby subscribe for the Issued Options for shares in {company} under the terms and conditions as set out in the ESOP Smart Contract at address {sc-address} and made available to me in [title of legal wrapper].
