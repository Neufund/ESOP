pragma solidity ^0.4.8;
import "./ESOPTypes.sol";
import "./EmployeesList.sol";
import "./OptionsCalculator.sol";
import "./CodeUpdateable.sol";
import './BaseOptionsConverter.sol';
import './ESOPMigration.sol';


contract ESOP is ESOPTypes, CodeUpdateable, TimeSource {
  // employee changed events
  event ESOPOffered(address indexed employee, address company, uint32 poolOptions, uint32 extraOptions);
  event EmployeeSignedToESOP(address indexed employee);
  event SuspendEmployee(address indexed employee, uint32 suspendedAt);
  event ContinueSuspendedEmployee(address indexed employee, uint32 continuedAt, uint32 suspendedPeriod);
  event TerminateEmployee(address indexed employee, address company, uint32 terminatedAt, TerminationType termType);
  event EmployeeOptionsExercised(address indexed employee, address exercisedFor, uint32 poolOptions, bool disableAcceleratedVesting);
  event EmployeeMigrated(address indexed employee, address migration, uint pool, uint extra);
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
  // total poolOptions in The Pool
  uint public totalPoolOptions;
  // ipfs hash of document establishing this ESOP
  bytes public ESOPLegalWrapperIPFSHash;
  // company address
  address public companyAddress;
  // root of immutable root of trust pointing to given ESOP implementation
  address public rootOfTrust;
  // default period for employee signature
  uint32 constant public MINIMUM_MANUAL_SIGN_PERIOD = 2 weeks;

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

  // migration destinations per employee
  mapping (address => ESOPMigration) private migrations;

  modifier hasEmployee(address e) {
    // will throw on unknown address
    if (!employees.hasEmployee(e))
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
    for (uint i = idx; i < employees.size(); i++) {
      address ea = employees.addresses(i);
      if (ea != 0) { // address(0) is deleted employee
        emp = _loademp(ea);
        // skip employees with no poolOptions and terminated employees
        if (emp.poolOptions > 0 && ( emp.state == EmployeeState.WaitingForSignature || emp.state == EmployeeState.Employed) ) {
          uint newoptions = optionsCalculator.calcNewEmployeePoolOptions(distributedOptions);
          emp.poolOptions += uint32(newoptions);
          distributedOptions -= uint32(newoptions);
          _saveemp(ea, emp);
        }
      }
    }
    return distributedOptions;
  }

  function removeEmployeesWithExpiredSignaturesAndReturnFadeout()
    onlyESOPOpen
    isCurrentCode
    public
  {
    // removes employees that didn't sign and sends their poolOptions back to the pool
    // computes fadeout for terminated employees and returns it to pool
    // we let anyone to call that method and spend gas on it
    Employee memory emp;
    uint32 ct = currentTime();
    for (uint i = 0; i < employees.size(); i++) {
      address ea = employees.addresses(i);
      if (ea != 0) { // address(0) is deleted employee
        var ser = employees.getSerializedEmployee(ea);
        emp = deserializeEmployee(ser);
        // remove employees with expired signatures
        if (emp.state == EmployeeState.WaitingForSignature && ct > emp.timeToSign) {
          remainingPoolOptions += distributeAndReturnToPool(emp.poolOptions, i+1);
          totalExtraOptions -= emp.extraOptions;
          // actually this just sets address to 0 so iterator can continue
          employees.removeEmployee(ea);
        }
        // return fadeout to pool
        if (emp.state == EmployeeState.Terminated && ct > emp.fadeoutStarts) {
          var (returnedPoolOptions, returnedExtraOptions) = optionsCalculator.calculateFadeoutToPool(ct, ser);
          if (returnedPoolOptions > 0 || returnedExtraOptions > 0) {
            employees.setFadeoutStarts(ea, ct);
            // options from fadeout are not distributed to other employees but returned to pool
            remainingPoolOptions += returnedPoolOptions;
            // we maintain extraPool for easier statistics
            totalExtraOptions -= returnedExtraOptions;
          }
        }
      }
    }
  }

  function openESOP(uint32 pTotalPoolOptions, bytes pESOPLegalWrapperIPFSHash)
    external
    onlyCompany
    onlyESOPNew
    isCurrentCode
    returns (ReturnCodes)
  {
    // options are stored in unit32
    if (pTotalPoolOptions > 1100000 || pTotalPoolOptions < 10000) {
      return _logerror(ReturnCodes.InvalidParameters);
    }

    totalPoolOptions = pTotalPoolOptions;
    remainingPoolOptions = totalPoolOptions;
    ESOPLegalWrapperIPFSHash = pESOPLegalWrapperIPFSHash;

    esopState = ESOPState.Open;
    ESOPOpened(companyAddress);
    return ReturnCodes.OK;
  }

  function offerOptionsToEmployee(address e, uint32 issueDate, uint32 timeToSign, uint32 extraOptions, bool poolCleanup)
    external
    onlyESOPOpen
    onlyCompany
    isCurrentCode
    returns (ReturnCodes)
  {
    // do not add twice
    if (employees.hasEmployee(e)) {
      return _logerror(ReturnCodes.InvalidEmployeeState);
    }
    if (timeToSign < currentTime() + MINIMUM_MANUAL_SIGN_PERIOD) {
      return _logerror(ReturnCodes.TooLate);
    }
    if (poolCleanup) {
      // recover poolOptions for employees with expired signatures
      // return fade out to pool
      removeEmployeesWithExpiredSignaturesAndReturnFadeout();
    }
    uint poolOptions = optionsCalculator.calcNewEmployeePoolOptions(remainingPoolOptions);
    if (poolOptions > 0xFFFFFFFF)
      throw;
    Employee memory emp = Employee({
      issueDate: issueDate, timeToSign: timeToSign, terminatedAt: 0, fadeoutStarts: 0, poolOptions: uint32(poolOptions),
      extraOptions: extraOptions, suspendedAt: 0, state: EmployeeState.WaitingForSignature, idx: 0
    });
    _saveemp(e, emp);
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
    isCurrentCode
    returns (ReturnCodes)
  {
    // do not add twice
    if (employees.hasEmployee(e)) {
      return _logerror(ReturnCodes.InvalidEmployeeState);
    }
    if (timeToSign < currentTime() + MINIMUM_MANUAL_SIGN_PERIOD) {
      return _logerror(ReturnCodes.TooLate);
    }
    Employee memory emp = Employee({
      issueDate: issueDate, timeToSign: timeToSign, terminatedAt: 0, fadeoutStarts: 0, poolOptions: 0,
      extraOptions: extraOptions, suspendedAt: 0, state: EmployeeState.WaitingForSignature, idx: 0
    });
    _saveemp(e, emp);
    totalExtraOptions += extraOptions;
    ESOPOffered(e, companyAddress, 0, extraOptions);
    return ReturnCodes.OK;
  }

  function increaseEmployeeExtraOptions(address e, uint32 extraOptions)
    external
    onlyESOPOpen
    onlyCompany
    isCurrentCode
    hasEmployee(e)
    returns (ReturnCodes)
  {
    Employee memory emp = _loademp(e);
    if (emp.state != EmployeeState.Employed && emp.state != EmployeeState.WaitingForSignature) {
      return _logerror(ReturnCodes.InvalidEmployeeState);
    }
    emp.extraOptions += extraOptions;
    _saveemp(e, emp);
    totalExtraOptions += extraOptions;
    ESOPOffered(e, companyAddress, 0, extraOptions);
    return ReturnCodes.OK;
  }

  function employeeSignsToESOP()
    external
    hasEmployee(msg.sender)
    onlyESOPOpen
    isCurrentCode
    returns (ReturnCodes)
  {
    Employee memory emp = _loademp(msg.sender);
    if (emp.state != EmployeeState.WaitingForSignature) {
      return _logerror(ReturnCodes.InvalidEmployeeState);
    }
    uint32 t = currentTime();
    if (t > emp.timeToSign) {
      remainingPoolOptions += distributeAndReturnToPool(emp.poolOptions, emp.idx);
      totalExtraOptions -= emp.extraOptions;
      employees.removeEmployee(msg.sender);
      return _logerror(ReturnCodes.TooLate);
    }
    employees.changeState(msg.sender, EmployeeState.Employed);
    EmployeeSignedToESOP(msg.sender);
    return ReturnCodes.OK;
  }

  function toggleEmployeeSuspension(address e, uint32 toggledAt)
    external
    onlyESOPOpen
    onlyCompany
    hasEmployee(e)
    isCurrentCode
    returns (ReturnCodes)
  {
    Employee memory emp = _loademp(e);
    if (emp.state != EmployeeState.Employed) {
      return _logerror(ReturnCodes.InvalidEmployeeState);
    }
    if (emp.suspendedAt == 0) {
      //suspend action
      emp.suspendedAt = toggledAt;
      SuspendEmployee(e, toggledAt);
    } else {
      if (emp.suspendedAt > toggledAt) {
        return _logerror(ReturnCodes.TooLate);
      }
      uint32 suspendedPeriod = toggledAt - emp.suspendedAt;
      // move everything by suspension period by changing issueDate
      emp.issueDate += suspendedPeriod;
      emp.suspendedAt = 0;
      ContinueSuspendedEmployee(e, toggledAt, suspendedPeriod);
    }
    _saveemp(e, emp);
    return ReturnCodes.OK;
  }

  function terminateEmployee(address e, uint32 terminatedAt, uint8 terminationType)
    external
    onlyESOPOpen
    onlyCompany
    hasEmployee(e)
    isCurrentCode
    returns (ReturnCodes)
  {
    // terminates an employee
    TerminationType termType = TerminationType(terminationType);
    Employee memory emp = _loademp(e);
    // todo: check termination time against issueDate
    if (terminatedAt < emp.issueDate) {
      return _logerror(ReturnCodes.InvalidParameters);
    }
    if (emp.state == EmployeeState.WaitingForSignature)
      termType = TerminationType.BadLeaver;
    else if (emp.state != EmployeeState.Employed) {
      return _logerror(ReturnCodes.InvalidEmployeeState);
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
    } else if (termType == TerminationType.BadLeaver) {
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

  function offerOptionsConversion(BaseOptionsConverter converter)
    external
    onlyESOPOpen
    onlyCompany
    isCurrentCode
    returns (ReturnCodes)
  {
    uint32 offerMadeAt = currentTime();
    if (converter.getExercisePeriodDeadline() - offerMadeAt < MINIMUM_MANUAL_SIGN_PERIOD) {
      return _logerror(ReturnCodes.TooLate);
    }
    // exerciseOptions must be callable by us
    if (converter.getESOP() != address(this)) {
      return _logerror(ReturnCodes.InvalidParameters);
    }
    // return to pool everything we can
    removeEmployeesWithExpiredSignaturesAndReturnFadeout();
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
    Employee memory emp = _loademp(employee);
    if (emp.state == EmployeeState.OptionsExercised) {
      return _logerror(ReturnCodes.InvalidEmployeeState);
    }
    // if we are burning options then send 0
    if (exerciseFor != address(0)) {
      var (pool, extra, bonus) = optionsCalculator.calculateOptionsComponents(serializeEmployee(emp),
        calcAtTime, conversionOfferedAt, disableAcceleratedVesting);
      }
    // call before options conversion contract to prevent re-entry
    employees.changeState(employee, EmployeeState.OptionsExercised);
    // exercise options in the name of employee and assign those to exerciseFor
    optionsConverter.exerciseOptions(exerciseFor, pool, extra, bonus, !disableAcceleratedVesting);
    EmployeeOptionsExercised(employee, exerciseFor, uint32(pool + extra + bonus), !disableAcceleratedVesting);
    return ReturnCodes.OK;
  }

  function employeeExerciseOptions(bool agreeToAcceleratedVestingBonusConditions)
    external
    onlyESOPConversion
    hasEmployee(msg.sender)
    isCurrentCode
    returns (ReturnCodes)
  {
    uint32 ct = currentTime();
    if (ct > exerciseOptionsDeadline) {
      return _logerror(ReturnCodes.TooLate);
    }
    return exerciseOptionsInternal(ct, msg.sender, msg.sender, !agreeToAcceleratedVestingBonusConditions);
  }

  function employeeDenyExerciseOptions()
    external
    onlyESOPConversion
    hasEmployee(msg.sender)
    isCurrentCode
    returns (ReturnCodes)
  {
    uint32 ct = currentTime();
    if (ct > exerciseOptionsDeadline) {
      return _logerror(ReturnCodes.TooLate);
    }
    // burn the options by sending to 0
    return exerciseOptionsInternal(ct, msg.sender, address(0), true);
  }

  function exerciseExpiredEmployeeOptions(address e, bool disableAcceleratedVesting)
    external
    onlyESOPConversion
    onlyCompany
    hasEmployee(e)
    isCurrentCode
  returns (ReturnCodes)
  {
    // company can convert options for any employee that did not converted (after deadline)
    uint32 ct = currentTime();
    if (ct <= exerciseOptionsDeadline) {
      return _logerror(ReturnCodes.TooEarly);
    }
    return exerciseOptionsInternal(ct, e, companyAddress, disableAcceleratedVesting);
  }

  function allowEmployeeMigration(address employee, ESOPMigration migration)
    external
    onlyESOPOpen
    hasEmployee(employee)
    onlyCompany
    isCurrentCode
    returns (ReturnCodes)
  {
    if (address(migration) == 0)
      throw;
    // only employed and terminated users may migrate
    Employee memory emp = _loademp(employee);
    if (emp.state != EmployeeState.Employed && emp.state != EmployeeState.Terminated) {
      return _logerror(ReturnCodes.InvalidEmployeeState);
    }
    migrations[employee] = migration; // can be cleared with 0 address
    return ReturnCodes.OK;
  }

  function employeeMigratesToNewESOP(ESOPMigration migration)
    external
    onlyESOPOpen
    hasEmployee(msg.sender)
    isCurrentCode
    returns (ReturnCodes)
  {
    // employee may migrate to new ESOP contract with different rules
    // if migration not set up by company then throw
    if (address(migration) == 0 || migrations[msg.sender] != migration)
      throw;
    // first give back what you already own
    removeEmployeesWithExpiredSignaturesAndReturnFadeout();
    // only employed and terminated users may migrate
    Employee memory emp = _loademp(msg.sender);
    if (emp.state != EmployeeState.Employed && emp.state != EmployeeState.Terminated) {
      return _logerror(ReturnCodes.InvalidEmployeeState);
    }
    // with accelerated vesting if possible - take out all possible options
    var (pool, extra, _) = optionsCalculator.calculateOptionsComponents(serializeEmployee(emp), currentTime(), 0, false);
    delete migrations[msg.sender];
    // execute migration procedure
    migration.migrate(msg.sender, pool, extra);
    // extra options are moved to new contract
    totalExtraOptions -= emp.state == EmployeeState.Employed ? emp.extraOptions : extra;
    // pool options are moved to new contract and removed from The Pool
    // please note that separate Pool will manage migrated options and
    // algorithm that returns to pool and distributes will not be used
    totalPoolOptions -= emp.state == EmployeeState.Employed ? emp.poolOptions : pool;
    // gone from current contract
    employees.removeEmployee(msg.sender);
    EmployeeMigrated(msg.sender, migration, pool, extra);
    return ReturnCodes.OK;
  }

  function calcEffectiveOptionsForEmployee(address e, uint32 calcAtTime)
    public
    constant
    hasEmployee(e)
    isCurrentCode
    returns (uint)
  {
    return optionsCalculator.calculateOptions(employees.getSerializedEmployee(e), calcAtTime, conversionOfferedAt, false);
  }

  function _logerror(ReturnCodes c) private returns (ReturnCodes) {
    ReturnCode(c);
    return c;
  }

  function _loademp(address e) private constant returns (Employee memory) {
    return deserializeEmployee(employees.getSerializedEmployee(e));
  }

  function _saveemp(address e, Employee memory emp) private {
    employees.setEmployee(e, emp.issueDate, emp.timeToSign, emp.terminatedAt, emp.fadeoutStarts, emp.poolOptions,
      emp.extraOptions, emp.suspendedAt, emp.state);
  }

  function completeCodeUpdate() public onlyOwner inCodeUpdate {
    employees.transferOwnership(msg.sender);
    CodeUpdateable.completeCodeUpdate();
  }

  function()
      payable
  {
      throw;
  }

  function ESOP(address company, address pRootOfTrust, OptionsCalculator pOptionsCalculator, EmployeesList pEmployeesList) {
    //esopState = ESOPState.New; // thats initial value
    companyAddress = company;
    rootOfTrust = pRootOfTrust;
    employees = pEmployeesList;
    optionsCalculator = pOptionsCalculator;
  }
}
