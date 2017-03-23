#!/usr/bin/env bash

cd contracts
solc --asm --abi --optimize *.sol -o ../solc
