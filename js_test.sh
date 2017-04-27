#!/usr/bin/env bash

rm -r test/*
cp -r js_tests/* test/
truffle test "$@"
exit $?
