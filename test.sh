#!/usr/bin/env bash

test="$1"
if [ -z "$1" ]
  then test="*"
fi

cp sol_tests/Test.DummyOptionConverter.sol contracts
cp sol_tests/Test.Types.sol contracts
cp sol_tests/Test.$test.sol contracts
dapple test --report --optimize
ec=$?
rm contracts/Test.*.sol
exit $ec
