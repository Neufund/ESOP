pragma solidity ^0.4.0;

import './ESOPTypes.sol';

contract ERC20OptionsConverter is IOptionsConverter, TimeSource
{
  address esopAddress;
  uint32 conversionDeadline;
  mapping(address => uint) internal balances;

  uint public totalSupply;

  event Transfer(address indexed from, address indexed to, uint value);
  event Creation(address indexed to, uint value);

  modifier converting() {
    if (currentTime() > conversionDeadline)
      throw;
    _;
  }

  modifier converted() {
    if (currentTime() <= conversionDeadline)
      throw;
    _;
  }


  function getESOP() public returns (address) {
    return esopAddress;
  }

  function getConversionDeadline() public returns(uint32) {
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

  function balanceOf(address _owner) constant converted public returns (uint balance) {
    return balances[_owner];
  }

  function () payable
  {
    throw;
  }

  function DummyOptionsConverter(address esop, uint32 deadline) {
    esopAddress = esop;
    conversionDeadline = deadline;
  }
}

contract ProceedsOptionsConverter is ERC20OptionsConverter
{
  mapping (address => uint) internal withdrawals;
  uint[] internal payouts;

  function makePayout() payable onlyOwner public {
    // it does not make sense to distribute less than ether
    if (msg.value < 1 ether)
      throw;
    payouts.push(msg.value);
  }

  function withdraw() public returns (uint) {
    // do not allow owner
    // withdraw for msg.sender
    uint balance = balanceOf(msg.sender);
    if (balance == 0)
      return 0;
    uint paymentId = withdrawals[msg.sender];
    // if all payouts for given token holder executed then exit
    if (paymentId == payouts.length)
      return 0;
    uint payout = 0;
    for (uint i = paymentId + 1; i <= payouts.length; i++)
    {
      // it is up to wei resolution, no point in rounding
      uint thisPayout = (payouts[i-1] * balance) / totalSupply;
      payout += thisPayout;
    }
    // change now to prevent re-entry
    withdrawals[msg.sender] = payouts.length;
    if(!msg.sender.send(payout))
      throw;
    return payout;
  }

  function transfer(address _to, uint _value) converted public {
    // if anything was withdrawn then block transfer to prevent multiple withdrawals
    // todo: we could allow transfer to new account (no token balance)
    if (withdrawals[_to] > 0 || withdrawals[msg.sender] > 0)
      throw;
    ERC20OptionsConverter.transfer(_to, _value);
  }
}
