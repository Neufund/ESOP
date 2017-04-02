#!/usr/bin/env bash

cd contracts
solc --abi --optimize --overwrite *.sol -o ../solc
