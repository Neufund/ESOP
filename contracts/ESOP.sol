pragma solidity ^0.4.0;
import "./ESOPTypes.sol";
import "./EmployeesList.sol";
import "./Upgradeable.sol";
import './BaseOptionsConverter.sol';


contract ESOP is ESOPTypes, Upgradeable, TimeSource, Math {
  // employee changed events
  event ESOPOffered(address indexed employee, address company, uint32 poolOptions, uint32 extraOptions);
  event EmployeeSignedToESOP(address indexed employee);
  event SuspendEmployee(address indexed employee, uint32 suspendedAt);
  event ContinueSuspendedEmployee(address indexed employee, uint32 continuedAt, uint32 suspendedPeriod);
  event TerminateEmployee(address indexed employee, address company, uint32 terminatedAt, TerminationType termType);
  event EmployeeOptionsExercised(address indexed employee, uint32 poolOptions);
  // esop changed events
  event ESOPOpened(address company);
  event OptionsConversionOffered(address company, address converter, uint32 convertedAt, uint32 conversionDeadline);
  enum ESOPState { New, Open, Conversion }
  // use retrun codes until revert opcode is implemented
  enum ReturnCodes { OK, InvalidEmployeeState, TooLate, InvalidParameters  }
  // event raised when return code from a function is not OK, when OK is returned one of events above is raised
  event ReturnCode(ReturnCodes rc);
  enum TerminationType { Regular, BadLeaver }

  //CONFIG
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
  // total poolOptions in The Pool
  uint public totalPoolOptions;
  // ipfs hash of document establishing this ESOP
  bytes public ESOPLegalWrapperIPFSHash;
  // company address
  address public companyAddress;
  // root of immutable root of trust pointing to given ESOP implementation
  address public rootOfTrust;
  // options strike price
  uint constant public strikePrice = 1;
  // scale of the emulated fixed point operations
  uint constant public FP_SCALE = 10000;

  // STATE
  // poolOptions that remain to be assigned
  uint public remainingPoolOptions;
  // state of ESOP
  ESOPState public esopState; // automatically sets to Open (0)
  // list of employees
  EmployeesList public employees;
  // how many extra options inserted
  uint public totalExtraOptions;
  // when conversion event happened
  uint32 public conversionOfferedAt;
  // employee conversion deadline
  uint32 public exerciseOptionsDeadline;
  // option conversion proxy
  BaseOptionsConverter public optionsConverter;


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

  modifier onlyCompany() {
    if (companyAddress != msg.sender)
      throw;
    _;
  }

  function distributeAndReturnToPool(uint distributedOptions, uint idx)
    internal
    returns (uint)
  {
    // enumerate all employees that were offered poolOptions after than fromIdx -1 employee
    Employee memory emp;
    for(uint i=idx; i< employees.size(); i++) {
      address ea = employees.addresses(i);
      if (ea != 0) { // address(0) is deleted employee
        var sere = employees.getSerializedEmployee(ea);
        assembly { emp := sere }
        // skip employees with no poolOptions and terminated employees
        if( emp.poolOptions > 0 && ( emp.state == EmployeeState.WaitingForSignature || emp.state == EmployeeState.Employed) ) {
          uint newoptions = calcNewEmployeePoolOptions(distributedOptions);
          emp.poolOptions += uint32(newoptions);
          distributedOptions -= uint32(newoptions);
          employees.setEmployee(ea, emp.issueDate, emp.timeToSign, emp.terminatedAt, emp.fadeoutStarts, emp.poolOptions,
            emp.extraOptions, emp.suspendedAt, emp.state);
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
          remainingPoolOptions += distributeAndReturnToPool(emp.poolOptions, i+1);
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
          uint vestedOptions = calcVestedOptions(emp.terminatedAt, emp.issueDate, emp.poolOptions);
          uint returnedPoolOptions = calcFadeout(emp.fadeoutStarts, emp.issueDate, emp.terminatedAt, emp.poolOptions, vestedOptions) -
            calcFadeout(t, emp.issueDate, emp.terminatedAt, emp.poolOptions, vestedOptions);
          uint vestedExtraOptions = calcVestedOptions(emp.terminatedAt, emp.issueDate, emp.extraOptions);
          uint returnedExtraOptions = calcFadeout(emp.fadeoutStarts, emp.issueDate, emp.terminatedAt, emp.extraOptions, vestedExtraOptions) -
            calcFadeout(t, emp.issueDate, emp.terminatedAt, emp.extraOptions, vestedExtraOptions);
          if (returnedPoolOptions > 0 || returnedExtraOptions > 0) {
            employees.setFadeoutStarts(ea, t);
            // options from fadeout are not distributed to other employees but returned to pool
            remainingPoolOptions += returnedPoolOptions;
            // we maintain extraPool for easier statistics
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
    // removes employees that didn't sign and sends their poolOptions back to the pool
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

  function openESOP(uint32 pcliffPeriod, uint32 pvestingPeriod, uint32 pResidualAmountPromille, uint32 pbonusOptionsPromille,
    uint32 pNewEmployeePoolPromille, uint32 ptotalPoolOptions, bytes pESOPLegalWrapperIPFSHash)
    external
    onlyCompany
    onlyESOPNew
    notInMigration
    returns (ReturnCodes)
  {
    // options are stored in unit32
    if (ptotalPoolOptions > 1000000 || pResidualAmountPromille > FP_SCALE || pbonusOptionsPromille > FP_SCALE ||
      pNewEmployeePoolPromille > FP_SCALE) {
      ReturnCode(ReturnCodes.InvalidParameters);
      return ReturnCodes.InvalidParameters;
    }

    cliffPeriod = pcliffPeriod;
    vestingPeriod = pvestingPeriod;
    maxFadeoutPromille = FP_SCALE - pResidualAmountPromille;
    bonusOptionsPromille = pbonusOptionsPromille;
    newEmployeePoolPromille = pNewEmployeePoolPromille;
    totalPoolOptions = ptotalPoolOptions;
    remainingPoolOptions = totalPoolOptions;
    ESOPLegalWrapperIPFSHash = pESOPLegalWrapperIPFSHash;

    esopState = ESOPState.Open;
    ESOPOpened(companyAddress);
    return ReturnCodes.OK;
  }

  function calcNewEmployeePoolOptions(uint remaining)
    internal
    constant
    returns (uint poolOptions)
  {
    return divRound(remaining * newEmployeePoolPromille, FP_SCALE);
  }

  function estimateNewEmployeePoolOptions()
    external
    constant
    returns (uint32)
  {
    // estimate number of poolOptions from the pool, this does not exec fadeout and does not remove unsigned employees
    return uint32(calcNewEmployeePoolOptions(remainingPoolOptions));
  }

  function offerOptionsToEmployee(address e, uint32 issueDate, uint32 timeToSign, uint32 extraOptions, bool poolCleanup)
    external
    onlyESOPOpen
    onlyCompany
    notInMigration
    returns (ReturnCodes)
  {
    // do not add twice
    if(employees.hasEmployee(e)) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    if (poolCleanup) {
      // recover poolOptions for employees with expired signatures
      removeEmployeesWithExpiredSignatures(currentTime());
      // return fade out to pool
      returnFadeoutToPool(currentTime());
    }
    uint poolOptions = calcNewEmployeePoolOptions(remainingPoolOptions);
    if (poolOptions > 0xFFFFFFFF)
      throw;
    employees.setEmployee(e, issueDate, timeToSign, 0, 0, uint32(poolOptions), extraOptions, 0, EmployeeState.WaitingForSignature );
    remainingPoolOptions -= poolOptions;
    totalExtraOptions += extraOptions;
    ESOPOffered(e, companyAddress, uint32(poolOptions), extraOptions);
    return ReturnCodes.OK;
  }

  // todo: implement group add someday, however func distributeAndReturnToPool gets very complicated
  // todo: function calcNewEmployeePoolOptions(uint remaining, uint8 groupSize)
  // todo: function addNewEmployeesToESOP(address[] emps, uint32 issueDate, uint32 timeToSign)

  function offerOptionsToEmployeeOnlyExtra(address e, uint32 issueDate, uint32 timeToSign, uint32 extraOptions)
    external
    onlyESOPOpen
    onlyCompany
    notInMigration
    returns (ReturnCodes)
  {
    // do not add twice
    if(employees.hasEmployee(e)) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    employees.setEmployee(e, issueDate, timeToSign, 0, 0, 0, extraOptions, 0, EmployeeState.WaitingForSignature );
    totalExtraOptions += extraOptions;
    ESOPOffered(e, companyAddress, 0, extraOptions);
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
      remainingPoolOptions += distributeAndReturnToPool(emp.poolOptions, emp.idx);
      totalExtraOptions -= emp.extraOptions;
      employees.removeEmployee(msg.sender);
      ReturnCode(ReturnCodes.TooLate);
      return ReturnCodes.TooLate;
    }
    employees.changeState(msg.sender, EmployeeState.Employed);
    EmployeeSignedToESOP(msg.sender);
    return ReturnCodes.OK;
  }

  function suspendEmployee(address e, uint32 suspendedAt)
    external
    onlyESOPOpen
    onlyCompany
    hasEmployee(e)
    notInMigration
    returns (ReturnCodes)
  {
    var sere = employees.getSerializedEmployee(e);
    Employee memory emp;
    assembly { emp := sere }
    if (emp.state != EmployeeState.Employed) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    employees.setEmployee(e, emp.issueDate, emp.timeToSign, emp.terminatedAt,
      emp.fadeoutStarts, emp.poolOptions, emp.extraOptions, suspendedAt, emp.state);
    SuspendEmployee(e, suspendedAt);
    return ReturnCodes.OK;
  }

  function continueSuspendedEmployee(address e, uint32 continueAt)
    external
    onlyESOPOpen
    onlyCompany
    hasEmployee(e)
    notInMigration
    returns (ReturnCodes)
  {
    var sere = employees.getSerializedEmployee(e);
    Employee memory emp;
    assembly { emp := sere }
    if (emp.state != EmployeeState.Employed) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    if (emp.suspendedAt > continueAt) {
      ReturnCode(ReturnCodes.TooLate);
      return ReturnCodes.TooLate;
    }
    uint32 suspendedPeriod = continueAt - emp.suspendedAt;
    // move everything by suspension period by changing issueDate
    employees.setEmployee(e, emp.issueDate + suspendedPeriod, emp.timeToSign, emp.terminatedAt,
      emp.fadeoutStarts, emp.poolOptions, emp.extraOptions, 0, emp.state);
    ContinueSuspendedEmployee(e, continueAt, suspendedPeriod);
    return ReturnCodes.OK;
  }

  function terminateEmployee(address e, uint32 terminatedAt, uint8 terminationType)
    external
    onlyESOPOpen
    onlyCompany
    hasEmployee(e)
    notInMigration
    returns (ReturnCodes)
  {
    // terminates an employee
    TerminationType termType = TerminationType(terminationType);
    var sere = employees.getSerializedEmployee(e);
    Employee memory emp;
    assembly { emp := sere }
    // todo: check termination time against issueDate
    if (terminatedAt < emp.issueDate) {
      ReturnCode(ReturnCodes.InvalidParameters);
      return ReturnCodes.InvalidParameters;
    }
    if (emp.state == EmployeeState.WaitingForSignature)
      termType = TerminationType.BadLeaver;
    else if (emp.state != EmployeeState.Employed) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    // how many poolOptions returned to pool
    uint returnedOptions;
    uint returnedExtraOptions;
    if (termType == TerminationType.Regular) {
      // regular termination, compute suspension
      if (emp.suspendedAt > 0 && emp.suspendedAt < terminatedAt)
        emp.issueDate += terminatedAt - emp.suspendedAt;
      // vesting applies
      returnedOptions = emp.poolOptions - calcVestedOptions(terminatedAt, emp.issueDate, emp.poolOptions);
      returnedExtraOptions = emp.extraOptions - calcVestedOptions(terminatedAt, emp.issueDate, emp.extraOptions);
      employees.terminateEmployee(e, emp.issueDate, terminatedAt, terminatedAt, EmployeeState.Terminated);
    }
    else if (termType == TerminationType.BadLeaver) {
      // bad leaver - employee is kicked out from ESOP, return all poolOptions
      returnedOptions = emp.poolOptions;
      returnedExtraOptions = emp.extraOptions;
      employees.removeEmployee(e);
    }
    remainingPoolOptions += distributeAndReturnToPool(returnedOptions, emp.idx);
    totalExtraOptions -= returnedExtraOptions;
    TerminateEmployee(e, companyAddress, terminatedAt, termType);
    return ReturnCodes.OK;
  }

  function offerOptionsConversion(uint32 convertedAt, BaseOptionsConverter converter )
    external
    onlyESOPOpen
    onlyCompany
    notInMigration
    returns (ReturnCodes)
  {
    // prevent stupid things, give at least two weeks for employees to convert
    if (convertedAt >= converter.getExerciseDeadline() || converter.getExerciseDeadline() + 2 weeks < currentTime()) {
      ReturnCode(ReturnCodes.TooLate);
      return ReturnCodes.TooLate;
    }
    // exerciseOptions must be callable by us
    if (converter.getESOP() != address(this)) {
      ReturnCode(ReturnCodes.InvalidParameters);
      return ReturnCodes.InvalidParameters;
    }
    // return to pool everything we can
    removeEmployeesWithExpiredSignatures(currentTime());
    returnFadeoutToPool(currentTime());
    // from now vesting and fadeout stops, no new employees may be added
    conversionOfferedAt = convertedAt;
    exerciseOptionsDeadline = converter.getExerciseDeadline();
    optionsConverter = converter;
    // this is very irreversible
    esopState = ESOPState.Conversion;
    OptionsConversionOffered(companyAddress, address(converter), convertedAt, exerciseOptionsDeadline);
    return ReturnCodes.OK;
  }

  function employeeExerciseOptions()
    external
    onlyESOPConversion
    hasEmployee(msg.sender)
    notInMigration
    returns (ReturnCodes)
  {
    uint32 ct = currentTime();
    if (ct > exerciseOptionsDeadline) {
      ReturnCode(ReturnCodes.TooLate);
      return ReturnCodes.TooLate;
    }
    Employee memory emp;
    var sere = employees.getSerializedEmployee(msg.sender);
    assembly { emp := sere }
    if (emp.state == EmployeeState.OptionsExercised) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    // this is ineffective as employee data will be fetched from storage again
    uint options = calcEffectiveOptionsForEmployee(msg.sender, ct);
    // call before options conversion contract to prevent re-entry
    employees.changeState(msg.sender, EmployeeState.OptionsExercised);
    optionsConverter.exerciseOptions(msg.sender, options);
    EmployeeOptionsExercised(msg.sender, uint32(options));
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
    if (effectiveTime < cliffPeriod)
      return 0;
    else
      return  effectiveTime < vestingPeriod ? divRound(options * effectiveTime, vestingPeriod) : options;
  }

  function calcFadeout(uint32 t, uint32 issueDate, uint32 terminatedAt, uint options, uint vestedOptions)
    internal
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

  function callEffectiveOptions(Employee memory emp, uint32 calcAtTime)
    internal
    constant
    returns (uint)
  {
    // no options for converted options or when esop is not singed
    if (emp.state == EmployeeState.OptionsExercised || emp.state == EmployeeState.WaitingForSignature)
      return 0;
    // no options when esop is being converted and conversion deadline expired
    bool isESOPConverted = esopState == ESOPState.Conversion && calcAtTime >= conversionOfferedAt; // this function time-travels
    if (isESOPConverted && calcAtTime > exerciseOptionsDeadline)
      return 0;
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
      vestedOptions = calcVestedOptions(calcVestingAt, emp.issueDate, issuedOptions);
    }
    // calc fadeout for terminated employees
    if (emp.state == EmployeeState.Terminated) {
      // use conversion event time to compute fadeout to stop fadeout on conversion IF not after conversion date
      vestedOptions = calcFadeout(isESOPConverted ? conversionOfferedAt : calcAtTime,
        emp.issueDate, emp.terminatedAt, issuedOptions, vestedOptions);
    }
    // exit bonus only on conversion event and for employees that are not terminated, no exception for good will termination
    // do not apply bonus for extraOptions
    uint bonus = (isESOPConverted && emp.state == EmployeeState.Employed) ?
      divRound(emp.poolOptions*vestedOptions*bonusOptionsPromille, FP_SCALE*issuedOptions) : 0;
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

  function simulateEffectiveOptionsForEmployee(uint32 issueDate, uint32 terminatedAt, uint32 poolOptions,
    uint32 extraOptions, uint32 suspendedAt, uint8 employeeState, uint32 calcAtTime)
    external
    constant
    notInMigration
    returns (uint)
  {
    Employee memory emp = Employee({issueDate: issueDate, terminatedAt: terminatedAt,
      poolOptions: poolOptions, extraOptions: extraOptions, state: EmployeeState(employeeState),
      timeToSign: issueDate+2 weeks, fadeoutStarts: terminatedAt, suspendedAt: suspendedAt,
      idx:1});
    return callEffectiveOptions(emp, calcAtTime);
  }

  function()
      payable
  {
      throw;
  }

  // todo: make parameters explicit
  function ESOP(address company, address pRootOfTrust) {
    esopState = ESOPState.New; // thats initial value
    employees = new EmployeesList();
    companyAddress = company;
    rootOfTrust = pRootOfTrust;
  }
}
