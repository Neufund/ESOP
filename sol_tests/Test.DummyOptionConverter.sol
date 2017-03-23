pragma solidity ^0.4.0;

import './ESOPTypes.sol';

contract DummyOptionsConverter is IOptionsConverter {
  address esopAddress;
  uint32 conversionDeadline;
  uint public totalConvertedOptions;

  function getESOP() public returns (address) {
    return esopAddress;
  }

  function getConversionDeadline() public returns (uint32) {
    return conversionDeadline;
  }

  function convertOptions(address employee, uint options) onlyESOP public {
    totalConvertedOptions += options;
  }

  function DummyOptionsConverter(address esop, uint32 deadline) {
    esopAddress = esop;
    conversionDeadline = deadline;
  }
}
