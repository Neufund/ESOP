pragma solidity ^0.4.0;

import './BaseOptionsConverter.sol';

contract DummyOptionsConverter is BaseOptionsConverter {
  address esopAddress;
  uint32 exercisePeriodDeadline;
  uint public totalConvertedOptions;

  function getESOP() public constant returns (address) {
    return esopAddress;
  }

  function getExercisePeriodDeadline() public constant returns (uint32) {
    return exercisePeriodDeadline;
  }

  function exerciseOptions(address employee, uint poolOptions, uint extraOptions, uint bonusOptions,
    bool acceptAdditionalConditions) onlyESOP public {
    totalConvertedOptions += poolOptions + extraOptions + bonusOptions;
  }

  function DummyOptionsConverter(address esop, uint32 exerciseDeadline) {
    esopAddress = esop;
    exercisePeriodDeadline = exerciseDeadline;
  }
}
