pragma solidity ^0.4.0;

contract BaseOptionsConverter {

  // modifiers are inherited, check `owned` pattern
  //   http://solidity.readthedocs.io/en/develop/contracts.html#function-modifiers
  modifier onlyESOP() {
    if (msg.sender != getESOP())
      throw;
    _;
  }

  // returns ESOP address which is a sole executor of exerciseOptions function
  function getESOP() public constant returns (address);
  // deadline for employees to exercise options
  function getExercisePeriodDeadline() public constant returns (uint32);

  // exercise of options for given employee and amount
  function exerciseOptions(address employee, uint poolOptions, uint extraOptions, uint bonusOptions,
    bool agreeToAcceleratedVestingBonusConditions) onlyESOP public;
}
