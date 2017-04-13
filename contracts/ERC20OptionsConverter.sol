pragma solidity ^0.4.0;
import './ESOPTypes.sol';
import './BaseOptionsConverter.sol';


contract ERC20OptionsConverter is BaseOptionsConverter, TimeSource, Math {
  // see base class for explanations
  address esopAddress;
  uint32 exercisePeriodDeadline;
  // balances for converted options
  mapping(address => uint) internal balances;
  // total supply
  uint public totalSupply;

  // deadline for all options conversion including company's actions
  uint32 public optionsConversionDeadline;

  event Transfer(address indexed from, address indexed to, uint value);

  modifier converting() {
    if (currentTime() >= exercisePeriodDeadline)
      // throw after deadline
      throw;
    _;
  }

  modifier converted() {
    if (currentTime() < optionsConversionDeadline)
      // throw before deadline
      throw;
    _;
  }


  function getESOP() public constant returns (address) {
    return esopAddress;
  }

  function getExercisePeriodDeadline() public constant returns(uint32) {
    return exercisePeriodDeadline;
  }

  function exerciseOptions(address employee, uint options, bool agreeToAcceleratedVestingBonusConditions)
    public
    onlyESOP
    converting
  {
    // if no overflow on totalSupply, no overflows later
    totalSupply = safeAdd(totalSupply, options);
    balances[employee] += options;
    Transfer(0, employee, options);
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

  function ERC20OptionsConverter(address esop, uint32 exerciseDeadline, uint32 conversionDeadline) {
    esopAddress = esop;
    exercisePeriodDeadline = exerciseDeadline;
    optionsConversionDeadline = conversionDeadline;
  }
}
