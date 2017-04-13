pragma solidity ^0.4.0;
import "./ESOPTypes.sol";

// todo: this should be a library
contract OptionsCalculator is Math, ESOPTypes {
  // cliff duration in seconds
  uint public cliffPeriod;
  // vesting duration in seconds
  uint public vestingPeriod;
  // maximum promille that can fade out
  uint public maxFadeoutPromille;
  // exit bonus promille
  uint public bonusOptionsPromille;
  // per mille of unassigned poolOptions that new employee gets
  uint public newEmployeePoolPromille;

  function calcNewEmployeePoolOptions(uint optionsInPool)
    public
    constant
    returns (uint)
  {
    return divRound(optionsInPool * newEmployeePoolPromille, FP_SCALE);
  }

  function calculateVestedOptions(uint t, uint vestingStarts, uint options)
    public
    constant
    returns (uint)
  {
    if (t <= vestingStarts)
      return 0;
    // apply vesting
    uint effectiveTime = t - vestingStarts;
    // if within cliff nothing is due
    if (effectiveTime < cliffPeriod)
      return 0;
    else
      return  effectiveTime < vestingPeriod ? divRound(options * effectiveTime, vestingPeriod) : options;
  }

  function applyFadeoutToOptions(uint32 t, uint32 issueDate, uint32 terminatedAt, uint options, uint vestedOptions)
    public
    constant
    returns (uint)
  {
    if (t < terminatedAt)
      return vestedOptions;
    uint timefromTermination = t - terminatedAt;
    // fadeout duration equals to employment duration
    uint employmentPeriod = terminatedAt - issueDate;
    // minimum value of options at the end of fadeout, it is a % of all employee's options
    uint minFadeValue = divRound(options * (FP_SCALE - maxFadeoutPromille), FP_SCALE);
    // however employee cannot have more than options after fadeout than he was vested at termination
    if (minFadeValue >= vestedOptions)
      return vestedOptions;
    return timefromTermination > employmentPeriod ?
      minFadeValue  :
      (minFadeValue + divRound((vestedOptions - minFadeValue) * (employmentPeriod - timefromTermination), employmentPeriod));
  }

  function calculateOptions(uint[9] employee, uint32 calcAtTime, uint32 conversionOfferedAt)
    public
    constant
    returns (uint)
  {
    Employee memory emp = deserializeEmployee(employee);
    // no options for converted options or when esop is not singed
    if (emp.state == EmployeeState.OptionsExercised || emp.state == EmployeeState.WaitingForSignature)
      return 0;
    // no options when esop is being converted and conversion deadline expired
    bool isESOPConverted = conversionOfferedAt > 0 && calcAtTime >= conversionOfferedAt; // this function time-travels
    uint issuedOptions = emp.poolOptions + emp.extraOptions;
    // employee with no options
    if (issuedOptions == 0) return 0;
    // if emp is terminated but we calc options before term, simulate employed again
    if (calcAtTime < emp.terminatedAt && emp.terminatedAt > 0)
      emp.state = EmployeeState.Employed;
    uint vestedOptions = issuedOptions;
    bool accelerateVesting = isESOPConverted && emp.state == EmployeeState.Employed;
    if (!accelerateVesting) {
      // choose vesting time for terminated employee to be termination event time IF not after calculation date
      uint32 calcVestingAt = emp.state == EmployeeState.Terminated ? emp.terminatedAt :
        (emp.suspendedAt > 0 && emp.suspendedAt < calcAtTime ? emp.suspendedAt : calcAtTime);
      vestedOptions = calculateVestedOptions(calcVestingAt, emp.issueDate, issuedOptions);
    }
    // calc fadeout for terminated employees
    if (emp.state == EmployeeState.Terminated) {
      // use conversion event time to compute fadeout to stop fadeout on conversion IF not after conversion date
      vestedOptions = applyFadeoutToOptions(isESOPConverted ? conversionOfferedAt : calcAtTime,
        emp.issueDate, emp.terminatedAt, issuedOptions, vestedOptions);
    }
    // exit bonus only on conversion event and for employees that still employed
    // do not apply bonus for extraOptions
    uint bonus = (isESOPConverted && emp.state == EmployeeState.Employed) ?
      divRound(emp.poolOptions*vestedOptions*bonusOptionsPromille, FP_SCALE*issuedOptions) : 0;
    return  vestedOptions + bonus;
  }

  function simulateOptions(uint32 issueDate, uint32 terminatedAt, uint32 poolOptions,
    uint32 extraOptions, uint32 suspendedAt, uint8 employeeState, uint32 calcAtTime)
    public
    constant
    returns (uint)
  {
    Employee memory emp = Employee({issueDate: issueDate, terminatedAt: terminatedAt,
      poolOptions: poolOptions, extraOptions: extraOptions, state: EmployeeState(employeeState),
      timeToSign: issueDate+2 weeks, fadeoutStarts: terminatedAt, suspendedAt: suspendedAt,
      idx:1});
    return calculateOptions(serializeEmployee(emp), calcAtTime, 0);
  }

  function OptionsCalculator(uint32 pcliffPeriod, uint32 pvestingPeriod, uint32 pResidualAmountPromille,
    uint32 pbonusOptionsPromille, uint32 pNewEmployeePoolPromille) {
    cliffPeriod = pcliffPeriod;
    vestingPeriod = pvestingPeriod;
    maxFadeoutPromille = FP_SCALE - pResidualAmountPromille;
    bonusOptionsPromille = pbonusOptionsPromille;
    newEmployeePoolPromille = pNewEmployeePoolPromille;
  }
}
