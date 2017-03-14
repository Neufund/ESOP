pragma solidity ^0.4.0;

import './ESOPTypes.sol';

contract DummyOptionsConverter is IOptionsConverter {
  address esopAddress;
  uint public totalConvertedOptions;

  function getESOP() public returns (address) {
    return esopAddress;
  }

  function convertOptions(address employee, uint options) onlyESOP public {
    totalConvertedOptions += options;
  }

  function DummyOptionsConverter(address esop) {
    esopAddress = esop;
  }
}
