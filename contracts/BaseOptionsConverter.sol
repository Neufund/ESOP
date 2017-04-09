pragma solidity ^0.4.0;

contract BaseOptionsConverter {

  // modifiers are inherited, check `owned` pattern
  //   http://solidity.readthedocs.io/en/develop/contracts.html#function-modifiers
  modifier onlyESOP() {
    if (msg.sender != getESOP())
      throw;
    _;
  }
  function getESOP() public constant returns (address);
  function getExerciseDeadline() public constant returns (uint32);

  // exercise of options for given employee and amount
  function exerciseOptions(address employee, uint options) onlyESOP public;
}
