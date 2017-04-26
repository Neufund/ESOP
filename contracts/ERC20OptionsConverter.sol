pragma solidity ^0.4.8;
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
    // throw after deadline
    if (currentTime() >= exercisePeriodDeadline)
      throw;
    _;
  }

  modifier converted() {
    // throw before deadline
    if (currentTime() < optionsConversionDeadline)
      throw;
    _;
  }


  function getESOP() public constant returns (address) {
    return esopAddress;
  }

  function getExercisePeriodDeadline() public constant returns(uint32) {
    return exercisePeriodDeadline;
  }

  function exerciseOptions(address employee, uint poolOptions, uint extraOptions, uint bonusOptions,
    bool agreeToAcceleratedVestingBonusConditions)
    public
    onlyESOP
    converting
  {
    // if no overflow on totalSupply, no overflows later
    uint options = safeAdd(safeAdd(poolOptions, extraOptions), bonusOptions);
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

  function () payable {
    throw;
  }

  function ERC20OptionsConverter(address esop, uint32 exerciseDeadline, uint32 conversionDeadline) {
    esopAddress = esop;
    exercisePeriodDeadline = exerciseDeadline;
    optionsConversionDeadline = conversionDeadline;
  }
}
