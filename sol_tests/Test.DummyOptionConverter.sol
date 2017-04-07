pragma solidity ^0.4.0;

import './BaseOptionsConverter.sol';

contract DummyOptionsConverter is BaseOptionsConverter {
  address esopAddress;
  uint32 conversionDeadline;
  uint public totalConvertedOptions;

  function getESOP() public constant returns (address) {
    return esopAddress;
  }

  function getConversionDeadline() public constant returns (uint32) {
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
