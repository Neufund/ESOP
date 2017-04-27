pragma solidity ^0.4.8;
import './ERC20OptionsConverter.sol';


contract ProceedsOptionsConverter is Ownable, ERC20OptionsConverter {
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
    for (uint i = paymentId; i<payouts.length; i++) {
      // it is safe to make payouts pro-rata: (1) token supply will not change - check converted/conversion modifiers
      // -- (2) balances will not change: check transfer override which limits transfer between accounts
      // NOTE: safeMul throws on overflow, can lock users out of their withdrawals if balance is very high
      // @remco I know. any suggestions? expression below gives most precision
      uint thisPayout = divRound(safeMul(payouts[i], balance), totalSupply);
      payout += thisPayout;
    }
    // change now to prevent re-entry (not necessary due to low send() gas limit)
    withdrawals[msg.sender] = payouts.length;
    if (payout > 0) {
      // now modify payout within 1000 weis as we had rounding errors coming from pro-rata amounts
      // @remco maximum rounding error is (num_employees * num_payments) / 2 with the mean 0
      // --- 1000 wei is still nothing, please explain me what problem you see here
      if ( absDiff(this.balance, payout) < 1000 wei )
        payout = this.balance; // send all
      //if(!msg.sender.call.value(payout)()) // re entry test
      //  throw;
      if (!msg.sender.send(payout))
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

  function ProceedsOptionsConverter(address esop, uint32 exerciseDeadline, uint32 conversionDeadline)
    ERC20OptionsConverter(esop, exerciseDeadline, conversionDeadline)
  {
  }
}
