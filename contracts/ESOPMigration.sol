pragma solidity ^0.4.0;
import "./ESOPTypes.sol";

contract ESOPMigration {
  modifier onlyESOP() {
    if (msg.sender != getESOP())
      throw;
    _;
  }

  // returns ESOP address which is a sole executor of exerciseOptions function
  function getESOP() public constant returns (address);

  // migrate employee to new ESOP contract, throws if not possible
  // in simplest case new ESOP contract should derive from this contract and implement abstract methods
  // employees list is available for inspection by employee address
  // poolOptions and extraOption is amount of options transferred out of old ESOP contract
  function migrate(address employee, uint poolOptions, uint extraOptions) onlyESOP public;
}
