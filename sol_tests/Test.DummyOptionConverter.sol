pragma solidity ^0.4.8;

import './BaseOptionsConverter.sol';

contract DummyOptionsConverter is BaseOptionsConverter {
  address esopAddress;
  uint32 exercisePeriodDeadline;
  uint public totalConvertedOptions;

  struct share {
    uint pool;
    uint extra;
    uint bonus;
    bool accel;
  }

  mapping(address => share) public shares;

  function getESOP() public constant returns (address) {
    return esopAddress;
  }

  function getExercisePeriodDeadline() public constant returns (uint32) {
    return exercisePeriodDeadline;
  }

  function getShare(address e) public constant returns (uint, uint, uint, bool) {
    share s = shares[e];
    return (s.pool, s.extra, s.bonus, s.accel);
  }

  function exerciseOptions(address employee, uint poolOptions, uint extraOptions, uint bonusOptions,
    bool acceptAdditionalConditions)
    public
    onlyESOP
  {
    totalConvertedOptions += poolOptions + extraOptions + bonusOptions;
    // overwrite previous share, do not add values for multiple conversions for single address
    shares[employee] = share({pool: poolOptions, extra: extraOptions, bonus: bonusOptions,
      accel: acceptAdditionalConditions});
  }

  function DummyOptionsConverter(address esop, uint32 exerciseDeadline) {
    esopAddress = esop;
    exercisePeriodDeadline = exerciseDeadline;
  }
}
