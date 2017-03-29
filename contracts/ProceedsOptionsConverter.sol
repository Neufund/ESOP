pragma solidity ^0.4.0;

import './ERC20OptionsConverter.sol';

contract ProceedsOptionsConverter is ERC20OptionsConverter {
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
    uint payout = 0;
    for (uint i = paymentId; i<payouts.length; i++)
    {
      // it is up to wei resolution, no point in rounding
      uint thisPayout = safeMul(payouts[i], balance) / totalSupply;
      payout += thisPayout;
    }
    // change now to prevent re-entry (not necessary due to low send() gas limit)
    withdrawals[msg.sender] = payouts.length;
    if (payout > 0) {
      // now modify payout within 100 weis as we had rounding errors coming from pro-rata amounts
      if ( absDiff(this.balance, payout) < 100 wei )
        payout = this.balance; // send all
      //if(!msg.sender.call.value(payout)()) // re entry test
      //  throw;
      if(!msg.sender.send(payout))
        throw;
    }
    return payout;
  }

  function transfer(address _to, uint _value) public converted {
    // if anything was withdrawn then block transfer to prevent multiple withdrawals
    // todo: we could allow transfer to new account (no token balance)
    // todo: we could allow transfer between account that fully withdrawn (but what's the point? -token has 0 value then)
    // todo: there are a few other edge cases where there's transfer and no double spending
    if (withdrawals[_to] > 0 || withdrawals[msg.sender] > 0)
      throw;
    ERC20OptionsConverter.transfer(_to, _value);
  }

  function ProceedsOptionsConverter(address esop, uint32 deadline) ERC20OptionsConverter(esop, deadline) { }
}