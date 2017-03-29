pragma solidity ^0.4.0;
import './ESOPTypes.sol';

contract ERC20OptionsConverter is IOptionsConverter, TimeSource, Math {
  address esopAddress;
  uint32 conversionDeadline;
  mapping(address => uint) internal balances;

  uint public totalSupply;

  event Transfer(address indexed from, address indexed to, uint value);
  event Creation(address indexed to, uint value);

  modifier converting() {
    if (currentTime() >= conversionDeadline)
      // throw after deadline
      throw;
    _;
  }

  modifier converted() {
    if (currentTime() < conversionDeadline)
      // throw before deadline
      throw;
    _;
  }


  function getESOP() public constant returns (address) {
    return esopAddress;
  }

  function getConversionDeadline() public constant returns(uint32) {
    return conversionDeadline;
  }

  function convertOptions(address employee, uint options) onlyESOP converting public {
    totalSupply += options;
    balances[employee] += options;
    Creation(employee, options);
  }

  function transfer(address _to, uint _value) converted public {
    if (balances[msg.sender] < _value)
      throw;
    balances[msg.sender] -= _value;
    balances[_to] += _value;
    Transfer(msg.sender, _to, _value);
  }

  function balanceOf(address _owner) constant public returns (uint balance) {
    return balances[_owner];
  }

  function () payable
  {
    throw;
  }

  function ERC20OptionsConverter(address esop, uint32 deadline) {
    esopAddress = esop;
    conversionDeadline = deadline;
  }
}