#!/usr/bin/env bash

cd contracts
solc --asm --abi --optimize ESOP.sol -o ../solc
