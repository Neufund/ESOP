#!/usr/bin/env bash

cp sol_tests/Test.DummyOptionConverter.sol contracts
cp sol_tests/Test.Types.sol contracts
cp sol_tests/Test.Frontier.sol contracts
dapple test --report --optimize
rm contracts/Test.*.sol
