#!/usr/bin/env bash

cp sol_tests/Test.DummyOptionConverter.sol contracts
cp sol_tests/Test.Types.sol contracts
cp sol_tests/Simulate.*.sol contracts
dapple test --report --optimize
rm contracts/Simulate.*.sol
rm contracts/Test.DummyOptionConverter.sol
rm contracts/Test.Types.sol
