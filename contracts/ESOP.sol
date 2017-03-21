pragma solidity ^0.4.0;
import "./ESOPTypes.sol";

contract ESOP is ESOPTypes, Upgradeable, TimeSource
{
  enum ESOPState { Open, Conversion }
  enum ReturnCodes { OK, InvalidEmployeeState, TooLate, InvalidParameters  }
  enum TerminationType { Regular, GoodWill, ForACause }

  //CONFIG
  // cliff duration in seconds
  uint public cliffDuration;
  // vesting duration in seconds
  uint public vestingDuration;
  // maximum promille that can fade out
  uint public maxFadeoutPromille;
  // exit bonus promille
  uint public exitBonusPromille;
  // per mille of unassigned options that new employee gets
  uint public newEmployeePoolPromille;
  // total options in base pool
  uint public totalOptions;
  // CEO address
  address public addressOfCEO;
  // scale of the promille
  uint public constant fpScale = 10000;

  // STATE
  // options that remain to be assigned
  uint public remainingOptions;
  // state of ESOP: open for new employees or during options conversion
  ESOPState public esopState; // automatically sets to Open (0)
  // list of employees
  EmployeesList public employees;
  // how many extra options inserted
  uint public totalExtraOptions;
  // when conversion event happened
  uint32 public conversionEventTime;
  // employee conversion deadline
  uint32 public employeeConversionDeadline;
  // option conversion proxy
  IOptionsConverter public optionsConverter;


  modifier hasEmployee(address e) {
    // will throw on unknown address
    if(!employees.hasEmployee(e))
      throw;
    _;
  }

  modifier onlyESOPOpen() {
    if (esopState != ESOPState.Open)
      throw;
    _;
  }

  modifier onlyESOPConversion() {
    if (esopState != ESOPState.Conversion)
      throw;
    _;
  }

  modifier onlyCEO() {
    if (addressOfCEO != msg.sender)
      throw;
    _;
  }

  function divRound(uint v, uint d) public constant returns(uint) {
    // round up if % is half or more
    return v/d + (v % d >= (d%2 == 1 ? d/2+1 : d/2) ? 1: 0);
  }

  function changeCEO(address newCEO)
    external
    onlyOwner
  {
    if (newCEO != address(0)) addressOfCEO = newCEO;
  }

  function distributeAndReturnToPool(uint distributedOptions, uint idx)
    internal
    returns (uint)
  {
    // enumerate all employees that joined later than fromIdx -1 employee
    Employee memory emp;
    for(uint i=idx; i< employees.size(); i++) {
      address ea = employees.addresses(i);
      if (ea != 0) { // address(0) is deleted employee
        var sere = employees.getSerializedEmployee(ea);
        assembly { emp := sere }
        // skip employees with no options and terminated employees
        if( emp.options > 0 && ( emp.state == EmployeeState.WaitingForSignature || emp.state == EmployeeState.Employed) ) {
          // we could handle Terminated employees as well: compute vesting on new options and add vested part to distributedOptions to pass it to others
          // however we decided not to give more options to terminated employees
          uint newoptions = calcNewEmployeeOptions(distributedOptions);
          emp.options += uint32(newoptions);
          distributedOptions -= uint32(newoptions);
          employees.setEmployee(ea, emp.vestingStarted, emp.timeToSign, emp.terminatedAt, emp.fadeoutStarts, emp.options, emp.extraOptions, emp.state);
        }
      }
    }
    return distributedOptions;
  }

  function removeEmployeesWithExpiredSignatures()
    onlyESOPOpen
    external
  {
    // removes employees that didn't sign and sends their options back to the pool
    // we let anyone to call that method and spend gas on it
    uint32 t = currentTime();
    Employee memory emp;
    for(uint i=0; i< employees.size(); i++) {
      address ea = employees.addresses(i);
      if (ea != 0) { // address(0) is deleted employee
        var sere = employees.getSerializedEmployee(ea);
        assembly { emp := sere }
        if (t > emp.timeToSign) {
          remainingOptions += distributeAndReturnToPool(emp.options, i+1);
          totalExtraOptions -= emp.extraOptions;
          // actually this just sets address to 0 so iterator can continue
          employees.removeEmployee(ea);
        }
      }
    }
  }

  function returnFadeoutToPool()
    onlyESOPOpen
    external
  {
    // computes fadeout for terminated employees and returns it to pool
    // we let anyone to call that method and spend gas on it
    uint32 t = currentTime();
    Employee memory emp;
    for(uint i=0; i< employees.size(); i++) {
      address ea = employees.addresses(i);
      if (ea != 0) { // address(0) is deleted employee
        var sere = employees.getSerializedEmployee(ea);
        assembly { emp := sere }
        // only terminated with not returned to pool
        if (emp.state == EmployeeState.Terminated && t != emp.fadeoutStarts) {
          uint vestedOptions = calcVestedOptions(emp.terminatedAt, emp.vestingStarted, emp.options);
          uint returnedOptions = calcFadeout(emp.fadeoutStarts, emp.vestingStarted, emp.terminatedAt, emp.options, vestedOptions) -
            calcFadeout(t, emp.vestingStarted, emp.terminatedAt, emp.options, vestedOptions);
          uint vestedExtraOptions = calcVestedOptions(emp.terminatedAt, emp.vestingStarted, emp.extraOptions);
          uint returnedExtraOptions = calcFadeout(emp.fadeoutStarts, emp.vestingStarted, emp.terminatedAt, emp.extraOptions, vestedExtraOptions) -
            calcFadeout(t, emp.vestingStarted, emp.terminatedAt, emp.extraOptions, vestedExtraOptions);
          if (returnedOptions > 0 || returnedExtraOptions > 0) {
            employees.setEmployee(employees.addresses(i), emp.vestingStarted, emp.timeToSign, emp.terminatedAt, t,
              emp.options, emp.extraOptions, EmployeeState.Terminated);
            // options from fadeout are not distributed to other employees but returned to pool
            remainingOptions += returnedOptions;
            totalExtraOptions -= returnedExtraOptions;
          }
        }
      }
    }
  }

  function calcNewEmployeeOptions(uint remaining)
    internal
    constant
    returns (uint options)
  {
    return divRound(remaining * newEmployeePoolPromille, fpScale);
  }

  function addNewEmployeeToESOP(address e, uint32 vestingStarts, uint32 timeToSign, uint32 extraOptions, bool poolCleanup)
    external
    onlyESOPOpen
    onlyCEO
    returns (ReturnCodes)
  {
    // do not add twice
    if(employees.hasEmployee(e))
      return ReturnCodes.InvalidEmployeeState;
    if (poolCleanup) {
      // recover options for employees with expired signatures
      this.removeEmployeesWithExpiredSignatures();
      // return fade out to pool
      this.returnFadeoutToPool();
    }
    // assign options for group of size 1 obviously
    uint options = calcNewEmployeeOptions(remainingOptions);
    if (options > 0xFFFF)
      throw;
    employees.setEmployee(e, vestingStarts, timeToSign, 0, 0, uint32(options), extraOptions, EmployeeState.WaitingForSignature );
    remainingOptions -= options;
    totalExtraOptions += extraOptions;
    return ReturnCodes.OK;
  }

  // todo: implement group add someday, however func distributeAndReturnToPool gets very complicated
  /*function calcNewEmployeeOptions(uint remaining, uint8 groupSize)
    internal
    constant
    returns (uint options)
  {
    for(uint i=0; i<groupSize; i++) {
      uint s = divRound(remaining * newEmployeePoolPromille, fpScale);
      options += s;
      remaining -= s;
    }
    return options/groupSize;
  }

  function addNewEmployeesToESOP(address[] emps, uint32 vestingStarts, uint32 timeToSign)
    external
    onlyESOPOpen
    onlyCEO
    returns (ReturnCodes)
  {
    // recover options for employees with expired signatures
    this.removeEmployeesWithExpiredSignatures();
    // return fade out to pool
    this.returnFadeoutToPool();
    // do not add twice
    for(uint i=0; i < emps.length; i++)
      if(employees.hasEmployee(emps[i]))
        return ReturnCodes.InvalidEmployeeState;
    // assign options for group of size 1 obviously
    uint options = calcNewEmployeeOptions(remainingOptions, uint8(emps.length));
    if (options > 0xFFFF)
      throw;
    for(i=0; i < emps.length; i++) {
      employees.setEmployee(emps[i], vestingStarts, timeToSign, 0, 0, uint32(options), 0, EmployeeState.WaitingForSignature );
      remainingOptions -= options;
    }
    return ReturnCodes.OK;
  }*/

  function addEmployeeWithExtraOptions(address e, uint32 vestingStarts, uint32 timeToSign, uint32 extraOptions)
    external
    onlyESOPOpen
    onlyCEO
    returns (ReturnCodes)
  {
    // do not add twice
    if(employees.hasEmployee(e))
      return ReturnCodes.InvalidEmployeeState;
    employees.setEmployee(e, vestingStarts, timeToSign, 0, 0, 0, extraOptions, EmployeeState.WaitingForSignature );
    totalExtraOptions += extraOptions;
    return ReturnCodes.OK;
  }

  function employeeSignsToESOP()
    external
    hasEmployee(msg.sender)
    onlyESOPOpen
    returns (ReturnCodes)
  {
    var sere = employees.getSerializedEmployee(msg.sender);
    Employee memory emp;
    assembly { emp := sere }
    if (emp.state != EmployeeState.WaitingForSignature)
      return ReturnCodes.InvalidEmployeeState;
    uint32 t = currentTime();
    if (t > emp.timeToSign) {
      remainingOptions += distributeAndReturnToPool(emp.options, emp.idx);
      totalExtraOptions -= emp.extraOptions;
      employees.removeEmployee(msg.sender);
      return ReturnCodes.TooLate;
    }
    employees.changeState(msg.sender, EmployeeState.Employed);
    return ReturnCodes.OK;
  }

  function terminateEmployee(address e, uint32 terminatedAt, uint8 terminationType)
    external
    onlyESOPOpen
    onlyCEO
    hasEmployee(e)
    returns (ReturnCodes)
  {
    // terminates an employee
    TerminationType termType = TerminationType(terminationType);
    var sere = employees.getSerializedEmployee(e);
    Employee memory emp;
    assembly { emp := sere }
    if (emp.state == EmployeeState.WaitingForSignature)
      termType = TerminationType.ForACause;
    else if (emp.state != EmployeeState.Employed)
      return ReturnCodes.InvalidEmployeeState;
    // how many options returned to pool
    uint returnedOptions = 0;
    uint returnedExtraOptions = 0;
    if (termType == TerminationType.Regular) {
      // regular termination - vesting applies
      returnedOptions = emp.options - calcVestedOptions(terminatedAt, emp.vestingStarted, emp.options);
      returnedExtraOptions = emp.extraOptions - calcVestedOptions(terminatedAt, emp.vestingStarted, emp.extraOptions);
    }
    else if (termType == TerminationType.ForACause) {
      // for a cause - employee is kicked out from ESOP, return all options
      returnedOptions = emp.options;
      returnedExtraOptions = emp.extraOptions;
    }
    // else good will - we let employee to keep all the options - already set to zero
    // terminate employee properly
    if (termType == TerminationType.ForACause)
      employees.removeEmployee(e);
    else
      employees.terminateEmployee(e, terminatedAt, terminatedAt,
        termType == TerminationType.GoodWill ? EmployeeState.GoodWillTerminated: EmployeeState.Terminated);
    remainingOptions += distributeAndReturnToPool(returnedOptions, emp.idx);
    totalExtraOptions -= returnedExtraOptions;
    return ReturnCodes.OK;
  }

  function esopConversionEvent(uint32 convertedAt, uint32 conversionDeadline , IOptionsConverter conversionProxy )
    external
    onlyESOPOpen
    onlyCEO
    returns (ReturnCodes)
  {
    // prevent stupid things, give at least two weeks for employees to convert
    if (convertedAt >= conversionDeadline || conversionDeadline + 2 weeks < currentTime())
      return ReturnCodes.TooLate;
    // convertOptions must be callable by us
    if (conversionProxy.getESOP() != address(this))
      return ReturnCodes.InvalidParameters;
    // return to pool everything we can
    this.removeEmployeesWithExpiredSignatures();
    this.returnFadeoutToPool();
    // from now vesting and fadeout stops, no new employees may be added
    conversionEventTime = convertedAt;
    employeeConversionDeadline = conversionDeadline;
    optionsConverter = conversionProxy;
    // this is very irreversible
    esopState = ESOPState.Conversion;
    return ReturnCodes.OK;
  }

  function employeeConvertsOptions()
    external
    onlyESOPConversion
    hasEmployee(msg.sender)
    returns (ReturnCodes)
  {
    uint32 ct = currentTime();
    if (ct > employeeConversionDeadline)
      return ReturnCodes.TooLate;
    Employee memory emp;
    var sere = employees.getSerializedEmployee(msg.sender);
    assembly { emp := sere }
    if (emp.state == EmployeeState.OptionsConverted)
      return ReturnCodes.InvalidEmployeeState;
    // this is ineffective as employee data will be fetched from storage again
    uint options = this.calcEffectiveOptionsForEmployee(msg.sender, ct);
    // call before options conversion contract to prevent re-entry
    employees.changeState(msg.sender, EmployeeState.OptionsConverted);
    optionsConverter.convertOptions(msg.sender, options);
    return ReturnCodes.OK;
  }

  function calcVestedOptions(uint t, uint vestingStarts, uint options)
    internal
    constant
    returns (uint)
  {
    // apply vesting
    uint effectiveTime = t - vestingStarts;
    // if within cliff nothing is due
    if (effectiveTime < cliffDuration)
      return 0;
    else
      return  effectiveTime < vestingDuration ? divRound(options * effectiveTime, vestingDuration) : options;
  }

  function calcFadeout(uint32 t, uint32 vestingStarted, uint32 terminatedAt, uint options, uint vestedOptions)
    internal
    constant
    returns (uint)
  {
    uint timefromTermination = t - terminatedAt;
    uint fadeoutDuration = terminatedAt - vestingStarted;
    // long return expression minimizing scaling errors
    uint minFadeValue = divRound(options * (fpScale - maxFadeoutPromille), fpScale);
    return timefromTermination > fadeoutDuration ?
      minFadeValue  :
      (minFadeValue + divRound((vestedOptions - minFadeValue) * (fadeoutDuration - timefromTermination), fadeoutDuration));
    /*uint effectiveFadeoutPromille = timefromTermination > fadeoutDuration
      ? maxFadeoutPromille : divRound(maxFadeoutPromille*timefromTermination, fadeoutDuration);
    // return fadeout amount
    return divRound(options * effectiveFadeoutPromille, fpScale);*/
  }

  function calcEffectiveOptionsForEmployee(address e, uint32 calcAtTime)
    external
    constant
    hasEmployee(e)
    returns (uint)
  {
    var sere = employees.getSerializedEmployee(e);
    Employee memory emp;
    assembly { emp := sere }
    // no more options for converted options or when esop is not singed
    if (emp.state == EmployeeState.OptionsConverted || emp.state == EmployeeState.WaitingForSignature)
      return 0;
    // no options when esop is being converted and conversion deadline expired
    if (esopState == ESOPState.Conversion && calcAtTime > employeeConversionDeadline)
      return 0;
    uint allOptions = emp.options + emp.extraOptions;
    // employee with no options
    if (allOptions == 0)
        return 0;
    // if conversion event was triggered OR employee was terminated in good will then vesting does not apply and full amount is due
    // otherwise calc vested options. for terminated employee use termination date to compute vesting, otherwise use 'now'
    bool skipVesting = (esopState == ESOPState.Conversion && emp.state == EmployeeState.Employed)
      || emp.state == EmployeeState.GoodWillTerminated;
    uint vestedOptions = skipVesting ?  allOptions:
      calcVestedOptions(emp.state == EmployeeState.Terminated ? emp.terminatedAt : calcAtTime, emp.vestingStarted, allOptions);
    // calc fadeout for terminated employees
    // use conversion event time to compute fadeout to stop fadeout when exit
    if (emp.state == EmployeeState.Terminated) {
      vestedOptions = calcFadeout(esopState == ESOPState.Conversion ? conversionEventTime : calcAtTime,
        emp.vestingStarted, emp.terminatedAt, allOptions, vestedOptions);
    }
    // exit bonus only on conversion event and for employees that are not terminated, no exception for good will termination
    // do not apply bonus for extraOptions
    uint bonus = (esopState == ESOPState.Conversion && emp.state == EmployeeState.Employed) ?
      divRound(emp.options*vestedOptions*exitBonusPromille, fpScale*allOptions) : 0;
    return  vestedOptions + bonus;
  }

  function()
      payable
  {
      throw;
  }


  // todo: make parameters explicit
  function ESOP() {
    // esopState = ESOPState.Open; // thats initial value
    employees = new EmployeesList();
    cliffDuration = 1 years;
    vestingDuration = 4 years;
    maxFadeoutPromille = 8000;
    exitBonusPromille = 2000;
    newEmployeePoolPromille = 1000;
    totalOptions = 100000;
    remainingOptions = totalOptions;
    addressOfCEO = owner;
    // check invalid ESOP configurations
    // 1. cliff must be higher than max fadout
    //if (divRound(totalOptions*cliffDuration,vestingDuration) >= divRound(totalOptions*(fpScale - maxFadeoutPromille), fpScale))
    //  throw;
  }
}
