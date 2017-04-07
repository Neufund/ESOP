pragma solidity ^0.4.0;
import "./ESOPTypes.sol";

contract ESOP is ESOPTypes, Upgradeable, TimeSource, Math {
  // employee changed events
  event NewEmployee(address indexed e, address ceo, uint32 options, uint32 extraOptions);
  event EmployeeSignedToESOP(address indexed e);
  event TerminateEmployee(address indexed e, address ceo, uint32 terminatedAt, TerminationType termType);
  event EmployeeOptionsConverted(address indexed e, uint32 options);
  // esop changed events
  event ESOPOpened(address ceo);
  event ESOPOptionsConversionStarted(address ceo, address converter, uint32 convertedAt, uint32 conversionDeadline);
  enum ESOPState { New, Open, Conversion }
  // use retrun codes until revert opcode is implemented
  enum ReturnCodes { OK, InvalidEmployeeState, TooLate, InvalidParameters  }
  // event raised when return code from a function is not OK, when OK is returned one of events above is raised
  event ReturnCode(ReturnCodes rc);
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
  // ipfs hash of document establishing this ESOP
  bytes public poolEstablishmentDocIPFSHash;
  // CEO address
  address public addressOfCEO;
  // root of immutable root of trust pointing to given ESOP implementation
  address public rootOfTrust;
  // scale of the emulated fixed point operations
  uint constant public FP_SCALE = 10000;

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

  modifier onlyESOPNew() {
    if (esopState != ESOPState.New)
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

  function removeEmployeesWithExpiredSignatures(uint32 t) internal {
    Employee memory emp;
    for(uint i=0; i< employees.size(); i++) {
      address ea = employees.addresses(i);
      if (ea != 0) { // address(0) is deleted employee
        var sere = employees.getSerializedEmployee(ea);
        assembly { emp := sere }
        if (t > emp.timeToSign && emp.state == EmployeeState.WaitingForSignature) {
          remainingOptions += distributeAndReturnToPool(emp.options, i+1);
          totalExtraOptions -= emp.extraOptions;
          // actually this just sets address to 0 so iterator can continue
          employees.removeEmployee(ea);
        }
      }
    }
  }

  function returnFadeoutToPool(uint32 t) internal {
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

  function removeEmployeesWithExpiredSignatures()
    onlyESOPOpen
    notInMigration
    public
  {
    // removes employees that didn't sign and sends their options back to the pool
    // we let anyone to call that method and spend gas on it
    removeEmployeesWithExpiredSignatures(currentTime());
  }

  function returnFadeoutToPool()
    onlyESOPOpen
    notInMigration
    external
  {
    // computes fadeout for terminated employees and returns it to pool
    // we let anyone to call that method and spend gas on it
    returnFadeoutToPool(currentTime());
  }

  function openESOP(uint32 pCliffDuration, uint32 pVestingDuration, uint32 pMaxFadeoutPromille, uint32 pExitBonusPromille,
    uint32 pNewEmployeePoolPromille, uint32 pTotalOptions, bytes pPoolEstablishmentDocIPFSHash)
    external
    onlyCEO
    onlyESOPNew
    notInMigration
    returns (ReturnCodes)
  {
    // options are stored in unit32
    if (pTotalOptions > 1000000 || pMaxFadeoutPromille > FP_SCALE || pExitBonusPromille > FP_SCALE ||
      pNewEmployeePoolPromille > FP_SCALE) {
      ReturnCode(ReturnCodes.InvalidParameters);
      return ReturnCodes.InvalidParameters;
    }

    cliffDuration = pCliffDuration;
    vestingDuration = pVestingDuration;
    maxFadeoutPromille = pMaxFadeoutPromille;
    exitBonusPromille = pExitBonusPromille;
    newEmployeePoolPromille = pNewEmployeePoolPromille;
    totalOptions = pTotalOptions;
    remainingOptions = totalOptions;
    poolEstablishmentDocIPFSHash = pPoolEstablishmentDocIPFSHash;

    esopState = ESOPState.Open;
    ESOPOpened(addressOfCEO);
    return ReturnCodes.OK;
  }

  function calcNewEmployeeOptions(uint remaining)
    internal
    constant
    returns (uint options)
  {
    return divRound(remaining * newEmployeePoolPromille, FP_SCALE);
  }

  function estimateNewEmployeeOptions()
    external
    constant
    returns (uint32)
  {
    // estimate number of options from the pool, this does not exec fadeout and does not remove unsigned employees
    return uint32(calcNewEmployeeOptions(remainingOptions));
  }

  function addNewEmployeeToESOP(address e, uint32 vestingStarts, uint32 timeToSign, uint32 extraOptions, bool poolCleanup)
    external
    onlyESOPOpen
    onlyCEO
    notInMigration
    returns (ReturnCodes)
  {
    // do not add twice
    if(employees.hasEmployee(e)) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    if (poolCleanup) {
      // recover options for employees with expired signatures
      removeEmployeesWithExpiredSignatures(currentTime());
      // return fade out to pool
      returnFadeoutToPool(currentTime());
    }
    // assign options for group of size 1 obviously
    uint options = calcNewEmployeeOptions(remainingOptions);
    if (options > 0xFFFFFFFF)
      throw;
    employees.setEmployee(e, vestingStarts, timeToSign, 0, 0, uint32(options), extraOptions, EmployeeState.WaitingForSignature );
    remainingOptions -= options;
    totalExtraOptions += extraOptions;
    NewEmployee(e, addressOfCEO, uint32(options), extraOptions);
    return ReturnCodes.OK;
  }

  // todo: implement group add someday, however func distributeAndReturnToPool gets very complicated
  // todo: function calcNewEmployeeOptions(uint remaining, uint8 groupSize)
  // todo: function addNewEmployeesToESOP(address[] emps, uint32 vestingStarts, uint32 timeToSign)

  function addEmployeeWithExtraOptions(address e, uint32 vestingStarts, uint32 timeToSign, uint32 extraOptions)
    external
    onlyESOPOpen
    onlyCEO
    notInMigration
    returns (ReturnCodes)
  {
    // do not add twice
    if(employees.hasEmployee(e)) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    employees.setEmployee(e, vestingStarts, timeToSign, 0, 0, 0, extraOptions, EmployeeState.WaitingForSignature );
    totalExtraOptions += extraOptions;
    NewEmployee(e, addressOfCEO, 0, extraOptions);
    return ReturnCodes.OK;
  }

  function employeeSignsToESOP()
    external
    hasEmployee(msg.sender)
    onlyESOPOpen
    notInMigration
    returns (ReturnCodes)
  {
    var sere = employees.getSerializedEmployee(msg.sender);
    Employee memory emp;
    assembly { emp := sere }
    if (emp.state != EmployeeState.WaitingForSignature) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    uint32 t = currentTime();
    if (t > emp.timeToSign) {
      remainingOptions += distributeAndReturnToPool(emp.options, emp.idx);
      totalExtraOptions -= emp.extraOptions;
      employees.removeEmployee(msg.sender);
      ReturnCode(ReturnCodes.TooLate);
      return ReturnCodes.TooLate;
    }
    employees.changeState(msg.sender, EmployeeState.Employed);
    EmployeeSignedToESOP(msg.sender);
    return ReturnCodes.OK;
  }

  function terminateEmployee(address e, uint32 terminatedAt, uint8 terminationType)
    external
    onlyESOPOpen
    onlyCEO
    hasEmployee(e)
    notInMigration
    returns (ReturnCodes)
  {
    // terminates an employee
    TerminationType termType = TerminationType(terminationType);
    var sere = employees.getSerializedEmployee(e);
    Employee memory emp;
    assembly { emp := sere }
    // todo: check termination time against vestingStarted
    if (terminatedAt < emp.vestingStarted) {
      ReturnCode(ReturnCodes.InvalidParameters);
      return ReturnCodes.InvalidParameters;
    }
    if (emp.state == EmployeeState.WaitingForSignature)
      termType = TerminationType.ForACause;
    else if (emp.state != EmployeeState.Employed) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    // how many options returned to pool
    uint returnedOptions;
    uint returnedExtraOptions;
    if (termType == TerminationType.Regular) {
      // regular termination - vesting applies
      returnedOptions = emp.options - calcVestedOptions(terminatedAt, emp.vestingStarted, emp.options);
      returnedExtraOptions = emp.extraOptions - calcVestedOptions(terminatedAt, emp.vestingStarted, emp.extraOptions);
      employees.terminateEmployee(e, terminatedAt, terminatedAt, EmployeeState.Terminated);
    }
    else if (termType == TerminationType.ForACause) {
      // for a cause - employee is kicked out from ESOP, return all options
      returnedOptions = emp.options;
      returnedExtraOptions = emp.extraOptions;
      employees.removeEmployee(e);
    } if (termType == TerminationType.GoodWill) {
      // else good will - we let employee to keep all the options
      returnedOptions = 0; // code duplicates for easier human readout
      returnedExtraOptions = 0;
      employees.terminateEmployee(e, terminatedAt, terminatedAt, EmployeeState.GoodWillTerminated);
    }
    remainingOptions += distributeAndReturnToPool(returnedOptions, emp.idx);
    totalExtraOptions -= returnedExtraOptions;
    TerminateEmployee(e, addressOfCEO, terminatedAt, termType);
    return ReturnCodes.OK;
  }

  function convertESOPOptions(uint32 convertedAt, IOptionsConverter converter )
    external
    onlyESOPOpen
    onlyCEO
    notInMigration
    returns (ReturnCodes)
  {
    // prevent stupid things, give at least two weeks for employees to convert
    if (convertedAt >= converter.getConversionDeadline() || converter.getConversionDeadline() + 2 weeks < currentTime()) {
      ReturnCode(ReturnCodes.TooLate);
      return ReturnCodes.TooLate;
    }
    // convertOptions must be callable by us
    if (converter.getESOP() != address(this)) {
      ReturnCode(ReturnCodes.InvalidParameters);
      return ReturnCodes.InvalidParameters;
    }
    // return to pool everything we can
    removeEmployeesWithExpiredSignatures(currentTime());
    returnFadeoutToPool(currentTime());
    // from now vesting and fadeout stops, no new employees may be added
    conversionEventTime = convertedAt;
    employeeConversionDeadline = converter.getConversionDeadline();
    optionsConverter = converter;
    // this is very irreversible
    esopState = ESOPState.Conversion;
    ESOPOptionsConversionStarted(addressOfCEO, address(converter), convertedAt, employeeConversionDeadline);
    return ReturnCodes.OK;
  }

  function employeeConvertsOptions()
    external
    onlyESOPConversion
    hasEmployee(msg.sender)
    notInMigration
    returns (ReturnCodes)
  {
    uint32 ct = currentTime();
    if (ct > employeeConversionDeadline) {
      ReturnCode(ReturnCodes.TooLate);
      return ReturnCodes.TooLate;
    }
    Employee memory emp;
    var sere = employees.getSerializedEmployee(msg.sender);
    assembly { emp := sere }
    if (emp.state == EmployeeState.OptionsConverted) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    // this is ineffective as employee data will be fetched from storage again
    uint options = calcEffectiveOptionsForEmployee(msg.sender, ct);
    // call before options conversion contract to prevent re-entry
    employees.changeState(msg.sender, EmployeeState.OptionsConverted);
    optionsConverter.convertOptions(msg.sender, options);
    EmployeeOptionsConverted(msg.sender, uint32(options));
    return ReturnCodes.OK;
  }

  function calcVestedOptions(uint t, uint vestingStarts, uint options)
    internal
    constant
    returns (uint)
  {
    if (t <= vestingStarts)
      return 0;
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
    if (t < terminatedAt)
      return vestedOptions;
    uint timefromTermination = t - terminatedAt;
    // fadeout duration equals to employment duration
    uint fadeoutDuration = terminatedAt - vestingStarted;
    // minimum value of options at the end of fadeout, it is a % of all employee's options
    uint minFadeValue = divRound(options * (FP_SCALE - maxFadeoutPromille), FP_SCALE);
    // however employee cannot have more than options after fadeout than he was vested at termination
    if (minFadeValue >= vestedOptions)
      return vestedOptions;
    return timefromTermination > fadeoutDuration ?
      minFadeValue  :
      (minFadeValue + divRound((vestedOptions - minFadeValue) * (fadeoutDuration - timefromTermination), fadeoutDuration));
  }

  function callEffectiveOptions(Employee memory emp, uint32 calcAtTime)
    internal
    constant
    returns (uint)
  {
    // no options for converted options or when esop is not singed
    if (emp.state == EmployeeState.OptionsConverted || emp.state == EmployeeState.WaitingForSignature)
      return 0;
    // no options when esop is being converted and conversion deadline expired
    bool isESOPConverted = esopState == ESOPState.Conversion && calcAtTime >= conversionEventTime; // this function time-travels
    if (isESOPConverted && calcAtTime > employeeConversionDeadline)
      return 0;
    uint allOptions = emp.options + emp.extraOptions;
    // employee with no options
    if (allOptions == 0) return 0;
    // if emp is terminated but we calc options before term, simulate employed again
    if (calcAtTime < emp.terminatedAt && emp.terminatedAt > 0)
      emp.state = EmployeeState.Employed;
    uint vestedOptions = allOptions;
    bool accelerateVesting = (isESOPConverted && emp.state == EmployeeState.Employed) || emp.state == EmployeeState.GoodWillTerminated;
    if (!accelerateVesting) {
      // choose vesting time for terminated employee to be termination event time IF not after calculation date
      vestedOptions = calcVestedOptions(emp.state == EmployeeState.Terminated ? emp.terminatedAt : calcAtTime,
        emp.vestingStarted, allOptions);
    }
    // calc fadeout for terminated employees
    if (emp.state == EmployeeState.Terminated) {
      // use conversion event time to compute fadeout to stop fadeout on conversion IF not after conversion date
      vestedOptions = calcFadeout(isESOPConverted ? conversionEventTime : calcAtTime,
        emp.vestingStarted, emp.terminatedAt, allOptions, vestedOptions);
    }
    // exit bonus only on conversion event and for employees that are not terminated, no exception for good will termination
    // do not apply bonus for extraOptions
    uint bonus = (isESOPConverted && emp.state == EmployeeState.Employed) ?
      divRound(emp.options*vestedOptions*exitBonusPromille, FP_SCALE*allOptions) : 0;
    return  vestedOptions + bonus;
  }

  function calcEffectiveOptionsForEmployee(address e, uint32 calcAtTime)
    public
    constant
    hasEmployee(e)
    notInMigration
    returns (uint)
  {
    var sere = employees.getSerializedEmployee(e);
    Employee memory emp;
    assembly { emp := sere }
    return callEffectiveOptions(emp, calcAtTime);
  }

  function simulateEffectiveOptionsForEmployee(uint32 vestingStarted, uint32 terminatedAt, uint32 options,
    uint32 extraOptions, uint8 employeeState, uint32 calcAtTime)
    external
    constant
    notInMigration
    returns (uint)
  {
    Employee memory emp = Employee({vestingStarted: vestingStarted, terminatedAt: terminatedAt,
      options: options, extraOptions: extraOptions, state: EmployeeState(employeeState),
      timeToSign: vestingStarted+2 weeks, fadeoutStarts: terminatedAt, idx:1});
    return callEffectiveOptions(emp, calcAtTime);
  }

  function()
      payable
  {
      throw;
  }

  // todo: make parameters explicit
  function ESOP(address ceo, address pRootOfTrust) {
    esopState = ESOPState.New; // thats initial value
    employees = new EmployeesList();
    addressOfCEO = ceo;
    rootOfTrust = pRootOfTrust;
  }
}
