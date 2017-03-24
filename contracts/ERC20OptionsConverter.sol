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

contract ProceedsOptionsConverter is ERC20OptionsConverter
{
  mapping (address => uint) internal withdrawals;
  uint[] internal payouts;

  function makePayout() converted payable onlyOwner public {
    // it does not make sense to distribute less than ether
    if (msg.value < 1 ether)
      throw;
    payouts.push(msg.value);
  }

  function withdraw() converted public returns (uint) {
    // withdraw for msg.sender
    uint balance = balanceOf(msg.sender);
    if (balance == 0)
      return 0;
    uint paymentId = withdrawals[msg.sender];
    // if all payouts for given token holder executed then exit
    if (paymentId == payouts.length)
      return 0;
    // if non existing withdrawal, then count from 1
    if (paymentId == 0) paymentId = 1;
    uint payout = 0;
    for (uint i = paymentId - 1; i<payouts.length; i++)
    {
      // it is up to wei resolution, no point in rounding
      // todo: use division library
      uint thisPayout = (payouts[i] * balance) / totalSupply;
      payout += thisPayout;
    }
    // change now to prevent re-entry
    withdrawals[msg.sender] = payouts.length;
    if (payout > 0) {
      // now modify payout within 100 weis as we had rounding errors coming from pro-rata amounts
      // if (this.balance )
      if(!msg.sender.send(payout))
        throw;
    }
    return payout;
  }

  function transfer(address _to, uint _value) converted public {
    // if anything was withdrawn then block transfer to prevent multiple withdrawals
    // todo: we could allow transfer to new account (no token balance)
    // todo: we could allow transfer between account that fully withdrawn (but what's the point? -token has 0 value then)
    // todo: there are a few other edge cases where there's transfer and no double spending
    if (withdrawals[_to] > 0 || withdrawals[msg.sender] > 0)
      throw;
    ERC20OptionsConverter.transfer(_to, _value);
  }

  function ProceedsOptionsConverter(address esop, uint32 deadline) ERC20OptionsConverter(esop, deadline) {
  }
}
