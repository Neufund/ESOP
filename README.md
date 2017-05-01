# Smart contracts and legal wrapper for implementing Employee Stock Options Plan

There is a lot of stuff below on what ESOP is, how vesting works etc. If you are just interested in smart contract info go [here](#smart-contracts), for info on testing and deployment go [here](#development).

## What is ESOP and why we do it?
ESOP stands for Employees Stock Options Plan. Many companies decide to include employees in company's success by offering them shares. Shares are typically available in form of options (mostly due to tax reasons) and are converted directly into cash when company has an IPO or gets acquired. There is a lot of interesting reasoning behind various ESOP structures and opinions when it works and when not. Here is a nice introduction: https://www.accion.org/sites/default/files/Accion%20Venture%20Lab%20-%20ESOP%20Best%20Practices.pdf

Neufund eats its own food and offers employees ESOP via a smart contract where options are represented as Ethereum tokens. Employees are still provided with ESOP terms in readable English (we call it *legal wrapper*) which is generated from before mentioned smart contract. Such construct replaces paper agreement employee signs and adds many interesting things on top.

1. Process of assigning options, vesting and converting are immutable and transparent (including rules on changing rules). Trustless trust is to large degree provided.
2. It is enforceable in off-chain court like standard paper agreement, *however* as smart contracts are self-enforcing a need for legal action should be negligible.
3. Typical criticism of ESOP is that you need to wait till the exit or IPO to get your shares and money. This is too long for being a real incentive. **This is not the case with tokenized options.** Use of Ethereum token extends opportunities to profit from options. For example **you can convert them into ERC20 compliant tokens when company is doing its ICO** or **make options directly trade-able** (via migration mechanism described later).
4. Smart contracts are self-enforcing and do all calculations and bookkeeping. They are very cheap once written and tested. ESOP d-app UI (https://github.com/Neufund/ESOP-ui) is easy to deploy with minimal maintenance costs.

## ESOP Algorithm
### ESOP Roles and Lifecycles
There are 3 main roles in ESOP project:
1. `owner` which represents company's sysadmin that deploys and upgrades smart contracts.
2. `company` which represents company management. Transactions signed by this role are deemed to be executed by Neufund (in case of our ESOP deployment). There are several reasons to have a separate account for this, but primarily we do not want `owner` to execute any ESOP logic, instead we provide nice d-app which our can be used by non-technical people.
3. `employee` which corresponds to employee receiving and exercising options.

Employee life within ESOP starts when company offers him/her options. Employee should sign the offer within provided deadline. This starts his/her employment period (counted from so called `issue date`) If employee leaves company then he goes to `terminated` state which also stops the vesting. Employee may be also fired in which case s/he is removed from contract. Finally when exit/ICO etc. happens, conversion offer is made by company to employee which when accepted puts employee in `converted` state.
Check `ESOPTypes.sol` for employee's possible states and properties.

ESOP itself has simple lifecycle. When deployed, it is in `new` state. It is opened by providing configuration parameters by `company` role. At that point all actions involving employees may happen. When there is conversion event like exit, `company` will switch ESOP into `conversion` state in which options may be exercised by employees.

### Assigning new options
Options are assigned to employees in two ways.

1. A method preferred by us that rewards risk taken. It simply gives more options to employees that came to work for us earlier, nothing else matters. It works as follows: there is a pool of 1 000 000 options of which employee 1 gets 10% which is 100 000. Employee 2 gets 10% of what remains in the pool (that is 900 000 options) which equals 90 000 and so on and so on. We call options distributed in this way `pool options`.
2. A method where company decides how much option it gives to employee. We call this options `extra options`.

Both methods can be combined. `pool options + extra options == issued options`

### Employee's options over time
Employee will not get all his/her options at the moment they are issued (however you can configure our smart contract to act in such way). Smart contract will release options up to all `issued options` with an algorithm called *vesting*.
![accelerated  vesting](/doc/accelerated_vesting.jpg)
As you can see there is a period of time called `cliff period` (for example 1 year, configurable, may be 0) during which employee does not get any options.

Then during the `vesting period` (period configurable, also may be 0), number of options increases up until `issued options`. In case of exit, IPO, ICO etc. additional `bonus options` (for example 20%, configurable) are added on top of issued options.

Please note that if exit, ICO etc. happens before `vesting period` is over, employee gets all `issued options` + `bonus` (we call this case `accelerated vesting.`).

### What happens when employee stops working for a company?
Sometimes people leave and ESOP smart contract handles that as well.

1. Company may remove employee from ESOP smart contract and cancel all his/her options. This is called `bad leaver event` in legal wrapper and may happen when for example employee breaks the law and needs to be fired. As you can expect such event cannot be defined in smart contract (there's no proper oracle yet in court system ;>) so this definition remains in legal wrapper.
2. Employee may just leave company and go working somewhere else. This case is more complicated.
![fadeout](/doc/esop_with_fadeout.jpg)
As you can see, vesting stops at the moment employee stops working at the company and all vested options are issued to employee. From that time amount of `vested options` is slowly decreasing down to `residual amount` sometimes called `floor`. Such process is called `fadeout` and fadeout period equals period of time employee worked at company. Smart contract may be configured for full fadeout and to not do any fadeout at all.

Terminated employee has no rights to `accelerated vesting` and no rights to `bonus options`.

### What is options conversion?
Here is the most interesting thing about ESOP smart contract. At some point in time (called `conversion event`), if company is successful it gets acquired or does an IPO and shareholders make a lot of money. This is what happens classically and we fully support it. We, however, extend this definition to any ICO, tokenization event or even further by allowing direct trade of vested options.

As you could expect there is no oracle for conversion events so those are defined in legal wrapper (see chapter 3). When such event happens employee may convert his/her options into shares, tokens or directly into EUR/ETH/BTC according to a Options Conversion Smart Contract (we have a few examples later) which will be provided by company when conversion event happens.

## Procedures and Security
Here's how Neufund handles security when issuing options.

1. All our employees get basic training in blockchain and security. We've published our training material [here](https://docs.google.com/document/d/171b6zvukuuV2UhWLJm9GTrLpIRaW16-xprH-JsRnlfc/edit#). May be pretty useful!
2. All our employees get [Nano Ledger](https://www.ledgerwallet.com/products/ledger-nano-s) and store their private keys in hardware wallets. We encourage employees to store their backup codes in some safe place (like at notary).
3. Backup codes of Neufund admin's Nano Ledger which is used to deploy smart contract and company management Nano Ledger are kept in a safe at notary office.
4. Options are offered via subscription forms implemented as d-app where we enforce usage of Nano Ledger for our employees (however, we support Metamask and other web3 providers).

Also it is clear for everyone that if you loose your private key you will loose all your options.

## Smart Contracts
### `ESOP` contract
`ESOP` smart contracts handles employees' lifecycle, manages options' pool and handles conversion offer via calling provided implementation of options conversion contracts. Implementation is pretty straightforward and functions more or less correspond to provisions in legal wrapper. Terminology is also preserved.
All non-const functions return "logic" errors via return codes and can throw only in case of generic problems like no permission to call a function or invalid state of smart contracts. Return codes correspond to `ReturnCode` event, in case of `OK` return code, specific event is logged (like `EmployeeSignedToESOP`). I hope `revert` opcode gets implemented soon!
`ESOP` aggregates the following contracts:
* `OptionsCalculator` which handles all options calculations like computing vesting, fadeout etc. and after configuring provides just a set of public constant methods.
* `EmployeesList` that contains iterable mapping of employees. Please note that `ESOP` is the sole writer to `EmployeesList` instance.

`ESOP` inherits from following contracts (I skip some obvious things like `Ownable`)
* `TimeSource` provides unified time source for all smart contracts in this project. It allows to mock-up time when not on mainnet.
* `ESOPTypes` defines `Employee` struct that is used everywhere in this project (I know, it should be a library)
* `CodeUpdateable` provides method to lock ESOP contract state when migrating to updated code (see later)

Ownership structure is worth mentioning. In `ESOP` and `OptionsCalculator` we have two owners:
* `owner` which deploys and upgrades code
* `company` that represents company's management

Please note that `owner` cannot execute any ESOP logic. S/he can deploy contracts and upgrade code but cannot open (activate) ESOP nor add employees.

#### ESOP configuration examples

|Description|Cliff Period|Vesting Period|Residual Amount %|Bonus Options %|New Employee Pool %|
|-----|----|----|----|----|----|
|Neufund configuration|1 year|4 years|50%|20%|10%|
|No cliff|0|4 years|20%|20%|10%|
|No fadeout|1 year|4 years|100%|20%|10%|
|Full fadeout|1 year|4 years|0|20%|10%|
|Disable pool options, only extra|1 year|4 years|20%|10%|0|
|Disable vesting, fadeout and bonus<sup>*</sup>|0|2 weeks|100%|0|10%|
<sup>*</sup> this option was not thoroughly tested, 2 weeks vesting period equals deadline for employee signature, cannot be 0 as unit tests are not prepared for that.

Neufund configuration sets options pool size to 1000080 and options per share to 360.

### Root of Trust
`RoT` is an immutable, deployed-once contract that points to other contracts that are deemed currently "supported/official/endorsed by company" etc. At this moment `RoT` points to current ESOP implementation (see code update and migration procedures). Our d-app uses `RoT` address (which never changes) to infer all other addresses it needs.
The right to change ESOP implementation and current owner `RoT` is with `company` not `owner`.

### Option Converters

Options converter implementation will correspond to given conversion scenario (for example cash payout after exit is different from getting tokens in ICO). However, each such contract must derive from `BaseOptionsConverter` which is provided to `ESOP` smart contract by `company`.
At minimum `exerciseOptions` function must be implemented (except two getters) that will be called by `ESOP` smart contract on behalf of employee when s/he decides to execute options. Please note that employee can burn his/her options - see comments in base class for details.
W provide two implementations of `BaseOptionsConverter`:
* `ERC20OptionsConverter` which converts options into ERC20 token.
* 'ProceedsOptionsConverter' that adds proceeds payouts via withdrawal pattern with several payouts made by company. Token trading is still enabled.

Both example converters are nicely tested but they are not considered production grade so beware.

### Code Update
Code update is strictly defined in legal wrapper chapter 8 and is reserved for bugfixing, optimization etc. where "spirit of the agreement" is not changed.

Code update starts via calling methods defined in `CodeUpdateable` base class from which `ESOP` contract derives. During code update only constant method of this contract are available so state cannot be changed. Whole procedure ends with replacing ESOP contract address in `RoT` contract instance.

There is a nice test/example of the whole procedure in `js_tests/test.CodeUpdate.js`, example updated ESOP is provided in `js_tests/UpdatedESOP.sol` and concept of data structure migration (`EmployeesList`) is demonstrated by `js_tests/UpdatedESOP.sol`.

Please note that all old ESOP contracts (including `ESOP`, `EmployeesList` and `OptionsCalculator`) selfdestruct at the end.

### Migration to new ESOP
Employee and company may agree to migrate to ESOP with different set of rules. This happens via `ESOPMigration` smart contract that is provided by company and then accepted by employee. Please check comments around `allowEmployeeMigration` and `employeeMigratesToNewESOP` functions in `ESOP` for many interesting details.
Migration process is strictly defined in the legal wrapper.

### TODO
* `ESOPTypes` should be a library that defines `Employee` type. Update is simple however `dapple` test framework does not appear to support libraries anymore and currently I will not port all the test to truffle (which lacks many useful features - see later).
* Options pool management functions (fadeout and options re-distribution, see `removeEmployeesWithExpiredSignaturesAndReturnFadeout`) should go to separate library.
* Port all solidity tests from `dapple` (which is sadly discontinued) to `truffle`.
* Let employees allow company to recover their options if they loose their private key.

## Legal Wrapper
Legal wrapper establishes ESOP and accompanying smart contracts as legally binding in off-chain legal system. Please read the source document in /legal folder, it is really interesting!

A fundamental problem we had to solve is **which contract form should prevail in case of conflict: computer code vs. terms in legal wrapper**. It's a story similar to multi-lingual legal documents (like you sign your ESOP with Chinese company which is originally in Chinese but translated to English).

* In case of ESOP agreement we have an asymmetric situation in terms of information and power. Employees are considered at disadvantage in both. In such case, to make agreement legally binding, **it must be proven that employee could understand what s/he was signing**. Thus we had to make **legal wrapper to prevail over smart contract** as it is easy for an employee to prove s/he could not understood the Solidity code and make court take his/her side. If there are any conflicts, English language is to prevail. This situation will persist until there is a smart contract language that people are able to understand or they all learn Solidity. Whichever happens first.
* In case of b2b agreements like when Limited Partner joins VC Fund, there is a symmetry both in information and power. This allows a smart contract to prevail (if you are rich person you can always ask your developer buddies to check the contract for you, still it may be much cheaper than to ask lawyers to do the same). In case of b2b the legal wrapper may be limited to just the most important business terms and still hold in court.

Other fundamental problem is a possible conflict of spirit and letter of the law (remember TheDAO?). Can we have bugs in the code or all code is law? We are clearly on the side of spirit of law prevailing and our legal wrapper (and corresponding smart contract code!) contains **bug fixing provision** and **provision to change ESOP rules** in chapter 8.

The same chapter defines a few other blockchain-related provisions like what we do in case of fork and what should happen when employee looses his/her private key (in short: s/he looses all their options so keep your keys safe).

Technically, wrapper is just a text document stored in IPFS, whose hash is added to ESOP smart contract. This document is filled with employee-specific variables and may be printed for reference. As you could expect we do not translate EVM bytecode to English.

## UI/D-APP
It's [here](https://github.com/Neufund/ESOP-ui). Please note that options subscription form has terminology and content defined in legal wrapper and d-app UI conforms to that.

## Development
### Compiler
We use solc 0.4.8. `Dapple` framework that we use for Solidity tests compiles with c++ solc that you should install from repo: http://solidity.readthedocs.io/en/develop/installing-solidity.html.
We use `truffle v3.2.1` for integration tests and compilation of deployed artifacts, which is using emscripten 0.4.8 solc build.
(FYI: bytecode produced by c++ and emscripten is identical: https://github.com/ethereum/solidity-test-bytecode)

### Running unit (solidity) tests
Solidity tests are run with `dapple`. This is unfortunate as `dapple` is discontinued and does not support libraries. There are a few things I liked about it: debug output, writing to CSV files from Solidity (nice thing for financial simulations), test for events and throws. Anyway, I'll never use it again and I plan to port current tests to truffle.
Solidity tests can be found in `sol_tests`, there are also shell scripts to make testing easier.
`./test.sh <test name>` will execute all test cases from test with given name. if name is not provided then all tests will be executed. For example  `./test.sh ReturnToPool` will run tests from `./sol_tests/Test.ReturnToPool.sol` file.

There are a few interesting test contracts defined:
* `EmpTester` which is a employee's proxy to ESOP contract that allows you to call its method with different senders.
* `ESOPMaker` which created `ESOP` smart contract with and necessary dependencies. Here you can mainpulate `ESOP` and `OptionsCalculator` parameters to match your case.
* `EmpReentry` that is doing re-entry attack on `ProceedsOptionsConverter`

There is also an ESOP simulator that stores results in `./solc/simulations.csv`, you can run it from `./simulate.sh` script.

### Running integration (js) tests
We use integration tests when we want to check smart contract behavior that spans many blocks, contracts are created and destroyed etc. Those tests are run in truffle from `./js_test.sh` script. Tests are defined in `./js_tests`. There is a network defined in `truffle.js` called `test` for which deployment scripts are deploying example options converters and opening the ESOP.

Run tests with:
`./js_test.sh --network test`

with testrepc run with
`testrpc --gasLimit=0x1500000 -i=192837992`

`test.CodeUpdate.js` is a notable test that demonstrated a whole procedure of code update of ESOP smart contract.

### Test deployment
We have defined following test deployments:

**test_deployment** where block gas limit approximates mainnet limit
Run testrpc with:
`testrpc --gasLimit=4100000  -i=192837991 --port=8546`
then run
`truffle deploy --network test_deployment`

**test** to run integration tests, see chapter above.

### Deployment on mainnet

### Make contract available in Etherscan

1. Put all contract files in one .sol files, remove imports etc. (is there Solidity preprocessor?)
2. Put this code into form in Etherscan, choose a compiler version
3. If smart contract has a constructor first obtain constructor parameters like for ESOP those would be
```
0x279084bb08100eebdb76b5d4eb250ecf0f12f29d options
0x54bd298c02177d717617d643bf9aedab7314b576 emp
0xa88828cbbd18244592f4bdd5f536648f95293427 rot
0x1078291bbcc539f51559f14bc57d1575d3801df8 comp
```
4. Insert combined file into Remix, then Create contract by giving parameters, put addresses in quotes like
`"0x1078291bbcc539f51559f14bc57d1575d3801df8", "0xa88828cbbd18244592f4bdd5f536648f95293427", "0x279084bb08100eebdb76b5d4eb250ecf0f12f29d", "0x54bd298c02177d717617d643bf9aedab7314b576"`
5. Use debugger to check callcode of create transaction. At the end of the Call Data, you'll find constructor parameters
6. You'll find them by comparing with bytecode, example
`0000000000000000000000001078291bbcc539f51559f14bc57d1575d3801df8000000000000000000000000a88828cbbd18244592f4bdd5f536648f95293427000000000000000000000000279084bb08100eebdb76b5d4eb250ecf0f12f29d00000000000000000000000054bd298c02177d717617d643bf9aedab7314b576`
7. Paste this into Etherescan and run,

## Steps to reproduce and verify bytecode deployed on mainnet/ropsten



--------------------
scratchbook
```
RoT.at(RoT.address).ESOPAddress()
ESOP.at(ESOP.address).rootOfTrust()

# setting up dev chain on parity and get some eth
parity --chain dev --jsonrpc-port 8444 ui
https://github.com/paritytech/parity/wiki/Private-development-chain

# run parity with unlocked account (deployment)
parity --chain dev --jsonrpc-cors "http://localhost:8081" --jsonrpc-hosts="all" --jsonrpc-port 8444 --unlock 0x00a329c0648769A73afAc7F9381E08FB43dBEA72,0x81866642828E92Aa2659F49925575827596b3443 --password ~/paritypass
# deploy with truffle
truffle migrate --network paritydev

# when you get `RPC io error: Address already in use (os error 98)` in parity remove pipe
rm /home/rudolfix/.local/share/io.parity.ethereum/jsonrpc.ipc

```
fineprints:
I hereby subscribe for the Issued Options for shares in {company} under the terms and conditions as set out in the ESOP Smart Contract at address {sc-address} and made available to me in [title of legal wrapper].
