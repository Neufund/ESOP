pragma solidity ^0.4.0;
import "./ESOPTypes.sol";
import "./EmployeesList.sol";
import "./OptionsCalculator.sol";
import "./Upgradeable.sol";
import './BaseOptionsConverter.sol';


contract ESOP is ESOPTypes, Upgradeable, TimeSource, Math {
  // employee changed events
  event ESOPOffered(address indexed employee, address company, uint32 poolOptions, uint32 extraOptions);
  event EmployeeSignedToESOP(address indexed employee);
  event SuspendEmployee(address indexed employee, uint32 suspendedAt);
  event ContinueSuspendedEmployee(address indexed employee, uint32 continuedAt, uint32 suspendedPeriod);
  event TerminateEmployee(address indexed employee, address company, uint32 terminatedAt, TerminationType termType);
  event EmployeeOptionsExercised(address indexed employee, address exercisedFor, uint32 poolOptions, bool disableAcceleratedVesting);
  // esop changed events
  event ESOPOpened(address company);
  event OptionsConversionOffered(address company, address converter, uint32 convertedAt, uint32 exercisePeriodDeadline);
  enum ESOPState { New, Open, Conversion }
  // use retrun codes until revert opcode is implemented
  enum ReturnCodes { OK, InvalidEmployeeState, TooLate, InvalidParameters, TooEarly  }
  // event raised when return code from a function is not OK, when OK is returned one of events above is raised
  event ReturnCode(ReturnCodes rc);
  enum TerminationType { Regular, BadLeaver }

  //CONFIG
  OptionsCalculator public optionsCalculator;
  // cliff duration in seconds
  function cliffPeriod() public constant returns(uint) { return optionsCalculator.cliffPeriod(); }
  // vesting duration in seconds
  function vestingPeriod() public constant returns(uint) { return optionsCalculator.vestingPeriod(); }
  // maximum promille that can fade out
  function maxFadeoutPromille() public constant returns(uint) { return optionsCalculator.maxFadeoutPromille(); }
  // exit bonus promille
  function bonusOptionsPromille() public constant returns(uint) { return optionsCalculator.bonusOptionsPromille(); }
  // per mille of unassigned poolOptions that new employee gets
  function newEmployeePoolPromille() public constant returns(uint) { return optionsCalculator.newEmployeePoolPromille(); }
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
  // default period for employee signature
  uint32 constant public waitForSignPeriod = 2 weeks;

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
        emp = deserializeEmployee(employees.getSerializedEmployee(ea));
        // skip employees with no poolOptions and terminated employees
        if( emp.poolOptions > 0 && ( emp.state == EmployeeState.WaitingForSignature || emp.state == EmployeeState.Employed) ) {
          uint newoptions = optionsCalculator.calcNewEmployeePoolOptions(distributedOptions);
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
        emp = deserializeEmployee(employees.getSerializedEmployee(ea));
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
        emp = deserializeEmployee(employees.getSerializedEmployee(ea));
        // only terminated with not returned to pool
        if (emp.state == EmployeeState.Terminated && t != emp.fadeoutStarts) {
          uint vestedOptions = optionsCalculator.calculateVestedOptions(emp.terminatedAt, emp.issueDate, emp.poolOptions);
          uint returnedPoolOptions = optionsCalculator.applyFadeoutToOptions(emp.fadeoutStarts, emp.issueDate, emp.terminatedAt, emp.poolOptions, vestedOptions) -
            optionsCalculator.applyFadeoutToOptions(t, emp.issueDate, emp.terminatedAt, emp.poolOptions, vestedOptions);
          uint vestedExtraOptions = optionsCalculator.calculateVestedOptions(emp.terminatedAt, emp.issueDate, emp.extraOptions);
          uint returnedExtraOptions = optionsCalculator.applyFadeoutToOptions(emp.fadeoutStarts, emp.issueDate, emp.terminatedAt, emp.extraOptions, vestedExtraOptions) -
            optionsCalculator.applyFadeoutToOptions(t, emp.issueDate, emp.terminatedAt, emp.extraOptions, vestedExtraOptions);
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

  function openESOP(OptionsCalculator pOptionsCalculator, EmployeesList pEmployeesList, uint32 ptotalPoolOptions, bytes pESOPLegalWrapperIPFSHash)
    external
    onlyCompany
    onlyESOPNew
    notInMigration
    returns (ReturnCodes)
  {
    // options are stored in unit32
    if (ptotalPoolOptions > 1000000 ||
      pOptionsCalculator.maxFadeoutPromille() > FP_SCALE || pOptionsCalculator.bonusOptionsPromille() > FP_SCALE ||
      pOptionsCalculator.newEmployeePoolPromille() > FP_SCALE) {
      ReturnCode(ReturnCodes.InvalidParameters);
      return ReturnCodes.InvalidParameters;
    }

    employees = pEmployeesList;
    optionsCalculator = pOptionsCalculator; //new OptionsCalculator(pcliffPeriod, pVestingPeriod, pResidualAmountPromille, pbonusOptionsPromille,
      //pNewEmployeePoolPromille);
    totalPoolOptions = ptotalPoolOptions;
    remainingPoolOptions = totalPoolOptions;
    ESOPLegalWrapperIPFSHash = pESOPLegalWrapperIPFSHash;

    esopState = ESOPState.Open;
    ESOPOpened(companyAddress);
    return ReturnCodes.OK;
  }

  function estimateNewEmployeePoolOptions()
    external
    constant
    returns (uint32)
  {
    // estimate number of poolOptions from the pool, this does not exec fadeout and does not remove unsigned employees
    return uint32(optionsCalculator.calcNewEmployeePoolOptions(remainingPoolOptions));
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
    if (timeToSign < currentTime() + waitForSignPeriod) {
      ReturnCode(ReturnCodes.TooLate);
      return ReturnCodes.TooLate;
    }
    if (poolCleanup) {
      // recover poolOptions for employees with expired signatures
      removeEmployeesWithExpiredSignatures(currentTime());
      // return fade out to pool
      returnFadeoutToPool(currentTime());
    }
    uint poolOptions = optionsCalculator.calcNewEmployeePoolOptions(remainingPoolOptions);
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
    Employee memory emp = deserializeEmployee(employees.getSerializedEmployee(msg.sender));
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
    Employee memory emp = deserializeEmployee(employees.getSerializedEmployee(e));
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
    Employee memory emp = deserializeEmployee(employees.getSerializedEmployee(e));
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
    Employee memory emp = deserializeEmployee(employees.getSerializedEmployee(e));
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
      returnedOptions = emp.poolOptions - optionsCalculator.calculateVestedOptions(terminatedAt, emp.issueDate, emp.poolOptions);
      returnedExtraOptions = emp.extraOptions - optionsCalculator.calculateVestedOptions(terminatedAt, emp.issueDate, emp.extraOptions);
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

  function cancelTerminatedEmployeeOptions() {
    // company may cancel options of terminated employee during first 6 months after termination
  }

  function offerOptionsConversion(BaseOptionsConverter converter )
    external
    onlyESOPOpen
    onlyCompany
    notInMigration
    returns (ReturnCodes)
  {
    uint32 offerMadeAt = currentTime();
    //
    if (converter.getExercisePeriodDeadline() - offerMadeAt < waitForSignPeriod) {
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
    conversionOfferedAt = offerMadeAt;
    exerciseOptionsDeadline = converter.getExercisePeriodDeadline();
    optionsConverter = converter;
    // this is very irreversible
    esopState = ESOPState.Conversion;
    OptionsConversionOffered(companyAddress, address(converter), offerMadeAt, exerciseOptionsDeadline);
    return ReturnCodes.OK;
  }

  function exerciseOptionsInternal(uint32 calcAtTime, address employee, address exerciseFor,
    bool disableAcceleratedVesting)
    internal
    returns (ReturnCodes)
  {
    Employee memory emp = deserializeEmployee(employees.getSerializedEmployee(employee));
    if (emp.state == EmployeeState.OptionsExercised) {
      ReturnCode(ReturnCodes.InvalidEmployeeState);
      return ReturnCodes.InvalidEmployeeState;
    }
    // terminate user with accelerated vesting disabled
    if (disableAcceleratedVesting) {
      emp.state = EmployeeState.Terminated;
      emp.terminatedAt = calcAtTime;
    }
    // if we are burning options then send 0
    uint options = 0;
    if (exerciseFor != address(0))
      options = optionsCalculator.calculateOptions(serializeEmployee(emp), calcAtTime, conversionOfferedAt);
    // call before options conversion contract to prevent re-entry
    employees.changeState(employee, EmployeeState.OptionsExercised);
    // exercise options in the name of employee and assign those to exerciseFor
    optionsConverter.exerciseOptions(exerciseFor, options, !disableAcceleratedVesting);
    EmployeeOptionsExercised(employee, exerciseFor, uint32(options), !disableAcceleratedVesting);
    return ReturnCodes.OK;
  }

  function employeeExerciseOptions(bool agreeToAcceleratedVestingBonusConditions)
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
    return exerciseOptionsInternal(ct, msg.sender, msg.sender, !agreeToAcceleratedVestingBonusConditions);
  }

  function employeeDenyExerciseOptions()
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
    // burn the options by sending to 0
    return exerciseOptionsInternal(ct, msg.sender, address(0), true);
  }

  function exerciseExpiredEmployeeOptions(address employee, bool disableAcceleratedVesting)
    external
    onlyESOPConversion
    onlyCompany
    notInMigration
  returns (ReturnCodes)
  {
    // company can convert options for any employee that did not converted (after deadline)
    uint32 ct = currentTime();
    if (ct <= exerciseOptionsDeadline) {
      ReturnCode(ReturnCodes.TooEarly);
      return ReturnCodes.TooEarly;
    }
    return exerciseOptionsInternal(ct, employee, companyAddress, disableAcceleratedVesting);
  }

  /*function employeeMigratesToNewESOP(ESOPMigration migration) {
    // employee may migrate to new ESOP contract with different rules
  }*/

  function calcEffectiveOptionsForEmployee(address e, uint32 calcAtTime)
    public
    constant
    hasEmployee(e)
    notInMigration
    returns (uint)
  {
    return optionsCalculator.calculateOptions(employees.getSerializedEmployee(e), calcAtTime, conversionOfferedAt);
  }

  function()
      payable
  {
      throw;
  }

  // todo: make parameters explicit
  function ESOP(address company, address pRootOfTrust) {
    esopState = ESOPState.New; // thats initial value
    companyAddress = company;
    rootOfTrust = pRootOfTrust;
  }
}
