#!/usr/bin/env bash

cd contracts
solc --asm --abi --optimize --overwrite *.sol -o ../solc
