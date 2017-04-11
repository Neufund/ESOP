#!/usr/bin/env bash

cd contracts
solc --abi --optimize --bin --overwrite *.sol -o ../solc
