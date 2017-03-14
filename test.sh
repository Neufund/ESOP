#!/usr/bin/env bash

cp sol_tests/Test.*.sol contracts
dapple test --report
rm contracts/Test.*.sol
