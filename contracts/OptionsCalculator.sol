pragma solidity ^0.4.8;
import "./ESOPTypes.sol";


contract OptionsCalculator is Ownable, Destructable, Math, ESOPTypes {
  // cliff duration in seconds
  uint public cliffPeriod;
  // vesting duration in seconds
  uint public vestingPeriod;
  // maximum promille that can fade out
  uint public maxFadeoutPromille;
  // minimal options after fadeout
  function residualAmountPromille() public constant returns(uint) { return FP_SCALE - maxFadeoutPromille; }
  // exit bonus promille
  uint public bonusOptionsPromille;
  // per mille of unassigned poolOptions that new employee gets
  uint public newEmployeePoolPromille;
  // options per share
  uint public optionsPerShare;
  // options strike price
  uint constant public STRIKE_PRICE = 1;
  // company address
  address public companyAddress;
  // checks if calculator i initialized
  function hasParameters() public constant returns(bool) { return optionsPerShare > 0; }

  modifier onlyCompany() {
    if (companyAddress != msg.sender)
      throw;
    _;
  }

  function calcNewEmployeePoolOptions(uint remainingPoolOptions)
    public
    constant
    returns (uint)
  {
    return divRound(remainingPoolOptions * newEmployeePoolPromille, FP_SCALE);
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

  function calculateOptionsComponents(uint[9] employee, uint32 calcAtTime, uint32 conversionOfferedAt,
    bool disableAcceleratedVesting)
    public
    constant
    returns (uint, uint, uint)
  {
    // returns tuple of (vested pool options, vested extra options, bonus)
    Employee memory emp = deserializeEmployee(employee);
    // no options for converted options or when esop is not singed
    if (emp.state == EmployeeState.OptionsExercised || emp.state == EmployeeState.WaitingForSignature)
      return (0,0,0);
    // no options when esop is being converted and conversion deadline expired
    bool isESOPConverted = conversionOfferedAt > 0 && calcAtTime >= conversionOfferedAt; // this function time-travels
    uint issuedOptions = emp.poolOptions + emp.extraOptions;
    // employee with no options
    if (issuedOptions == 0)
      return (0,0,0);
    // if emp is terminated but we calc options before term, simulate employed again
    if (calcAtTime < emp.terminatedAt && emp.terminatedAt > 0)
      emp.state = EmployeeState.Employed;
    uint vestedOptions = issuedOptions;
    bool accelerateVesting = isESOPConverted && emp.state == EmployeeState.Employed && !disableAcceleratedVesting;
    if (!accelerateVesting) {
      // choose vesting time
      uint32 calcVestingAt = emp.state ==
        // if terminated then vesting calculated at termination
        EmployeeState.Terminated ? emp.terminatedAt :
        // if employee is supended then compute vesting at suspension time
        (emp.suspendedAt > 0 && emp.suspendedAt < calcAtTime ? emp.suspendedAt :
        // if conversion offer then vesting calucated at time the offer was made
        conversionOfferedAt > 0 ? conversionOfferedAt :
        // otherwise use current time
        calcAtTime);
      vestedOptions = calculateVestedOptions(calcVestingAt, emp.issueDate, issuedOptions);
    }
    // calc fadeout for terminated employees
    if (emp.state == EmployeeState.Terminated) {
      // use conversion event time to compute fadeout to stop fadeout on conversion IF not after conversion date
      vestedOptions = applyFadeoutToOptions(isESOPConverted ? conversionOfferedAt : calcAtTime,
        emp.issueDate, emp.terminatedAt, issuedOptions, vestedOptions);
    }
    var (vestedPoolOptions, vestedExtraOptions) = extractVestedOptionsComponents(emp.poolOptions, emp.extraOptions, vestedOptions);
    // if (vestedPoolOptions + vestedExtraOptions != vestedOptions) throw;
    return  (vestedPoolOptions, vestedExtraOptions,
      accelerateVesting ? divRound(vestedPoolOptions*bonusOptionsPromille, FP_SCALE) : 0 );
  }

  function calculateOptions(uint[9] employee, uint32 calcAtTime, uint32 conversionOfferedAt, bool disableAcceleratedVesting)
    public
    constant
    returns (uint)
  {
    var (vestedPoolOptions, vestedExtraOptions, bonus) = calculateOptionsComponents(employee, calcAtTime,
      conversionOfferedAt, disableAcceleratedVesting);
    return vestedPoolOptions + vestedExtraOptions + bonus;
  }

  function extractVestedOptionsComponents(uint issuedPoolOptions, uint issuedExtraOptions, uint vestedOptions)
    public
    constant
    returns (uint, uint)
  {
    // breaks down vested options into pool options and extra options components
    if (issuedExtraOptions == 0)
      return (vestedOptions, 0);
    uint poolOptions = divRound(issuedPoolOptions*vestedOptions, issuedPoolOptions + issuedExtraOptions);
    return (poolOptions, vestedOptions - poolOptions);
  }

  function calculateFadeoutToPool(uint32 t, uint[9] employee)
    public
    constant
    returns (uint, uint)
  {
    Employee memory emp = deserializeEmployee(employee);

    uint vestedOptions = calculateVestedOptions(emp.terminatedAt, emp.issueDate, emp.poolOptions);
    uint returnedPoolOptions = applyFadeoutToOptions(emp.fadeoutStarts, emp.issueDate, emp.terminatedAt, emp.poolOptions, vestedOptions) -
      applyFadeoutToOptions(t, emp.issueDate, emp.terminatedAt, emp.poolOptions, vestedOptions);
    uint vestedExtraOptions = calculateVestedOptions(emp.terminatedAt, emp.issueDate, emp.extraOptions);
    uint returnedExtraOptions = applyFadeoutToOptions(emp.fadeoutStarts, emp.issueDate, emp.terminatedAt, emp.extraOptions, vestedExtraOptions) -
      applyFadeoutToOptions(t, emp.issueDate, emp.terminatedAt, emp.extraOptions, vestedExtraOptions);

    return (returnedPoolOptions, returnedExtraOptions);
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
    return calculateOptions(serializeEmployee(emp), calcAtTime, 0, false);
  }

  function setParameters(uint32 pCliffPeriod, uint32 pVestingPeriod, uint32 pResidualAmountPromille,
    uint32 pBonusOptionsPromille, uint32 pNewEmployeePoolPromille, uint32 pOptionsPerShare)
    external
    onlyCompany
  {
    if (pResidualAmountPromille > FP_SCALE || pBonusOptionsPromille > FP_SCALE || pNewEmployeePoolPromille > FP_SCALE
     || pOptionsPerShare == 0)
      throw;
    if (pCliffPeriod > pVestingPeriod)
      throw;
    // initialization cannot be called for a second time
    if (hasParameters())
      throw;
    cliffPeriod = pCliffPeriod;
    vestingPeriod = pVestingPeriod;
    maxFadeoutPromille = FP_SCALE - pResidualAmountPromille;
    bonusOptionsPromille = pBonusOptionsPromille;
    newEmployeePoolPromille = pNewEmployeePoolPromille;
    optionsPerShare = pOptionsPerShare;
  }

  function OptionsCalculator(address pCompanyAddress) {
    companyAddress = pCompanyAddress;
  }
}
