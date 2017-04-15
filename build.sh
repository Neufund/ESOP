#!/usr/bin/env bash

cd contracts
solc --abi --optimize --bin --asm --overwrite *.sol -o ../solc
