pragma solidity ^0.4.0;

contract Ownable {
  // replace with proper zeppelin smart contract
  address public owner;

  function Ownable() {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    if (msg.sender != owner)
      throw;
    _;
  }

  function transferOwnership(address newOwner) onlyOwner {
    if (newOwner != address(0)) owner = newOwner;
  }
}

contract TimeSource is Ownable {
  uint32 mockNow;
  
  function currentTime() public constant returns (uint32) {
    // we do not support dates much into future (Sun, 07 Feb 2106 06:28:15 GMT)
    if (block.timestamp > 0xFFFFFFFF)
      throw;
    // alow to return debug time on test nets etc.
    if (block.number > 3316029)
      return uint32(block.timestamp);
    else
      return mockNow > 0 ? mockNow : uint32(block.timestamp);
  }

  function mockTime(uint32 t) public onlyOwner {
    mockNow = t;
  }
}

contract RootOfTrust is Ownable
{
    address public ESOPAddress;

    // change esop contract
    function setESOP(address ESOP) public onlyOwner {
      ESOPAddress = ESOP;
    }
}


contract Upgradeable is Ownable {
    // allows to stop operations and upgrade
    enum MigrationState { Operational, OngoingMigration, Migrated}
    MigrationState public migrationState;

    modifier onlyOperational() {
      if (migrationState != MigrationState.Operational)
        throw;
      _;
    }

    modifier onlyOngoingMigration() {
      if (migrationState != MigrationState.OngoingMigration)
        throw;
      _;
    }
    modifier onlyMigrated() {
      if (migrationState != MigrationState.Migrated)
        throw;
      _;
    }

    function kill() onlyOwner onlyMigrated
    {
      selfdestruct(owner);
    }

    function beginMigration() public onlyOwner onlyOperational {
        migrationState = MigrationState.OngoingMigration;
    }

    function cancelMigration() public onlyOwner onlyOngoingMigration {
      migrationState = MigrationState.Operational;
    }

    function completeMigration() public onlyOwner onlyOngoingMigration {
      migrationState = MigrationState.Migrated;
    }
}

contract ESOPTypes
{
  // enums are numbered starting from 0. NotSet is used to check for non existing mapping
  enum EmployeeState { NotSet, WaitingForSignature, Employed, Terminated, GoodWillTerminated, OptionsConverted }
  // please note that 32 bit unsigned int is used to represent UNIX time which is enough to represent dates until Sun, 07 Feb 2106 06:28:15 GMT
  // storage access is optimized so struct layout is important
  struct Employee {
      // when vesting starts
      uint32 vestingStarted;
      // wait for employee signature until that time
      uint32 timeToSign;
      // date when employee was terminated, 0 for not terminated
      uint32 terminatedAt;
      // when fade out starts, 0 for not set, initally == terminatedAt
      // used only when calculating options returned to pool
      uint32 fadeoutStarts;
      // options employee gets (exit bonus not included)
      uint32 options;
      // extra options employee gets (neufund will not this option)
      uint32 extraOptions;
      // size of the group of the employees that were added together
      // uint8 groupSize;
      // what is employee current status, takes 8 bit in storage
      EmployeeState state;
      // index in iterable mapping
      uint16 idx;
      // reserve until full 256 bit word
      //uint56 reserved;
  }
}

contract EmployeesList is ESOPTypes, Ownable
{
  event CreateEmployee(address indexed e, uint32 options, uint32 extraOptions, uint16 idx);
  event UpdateEmployee(address indexed e, uint32 options, uint32 extraOptions, uint16 idx);
  mapping (address => Employee) employees;
  // addresses in the mapping, ever
  address[] public addresses;

  function size() external constant returns (uint16) {
    return uint16(addresses.length);
  }


  function setEmployee(address e, uint32 vestingStarted, uint32 timeToSign, uint32 terminatedAt, uint32 fadeoutStarts,
    uint32 options, uint32 extraOptions, EmployeeState state)
    external
    onlyOwner
    returns (bool isNew)
  {
    uint16 empIdx = employees[e].idx;
    if (empIdx == 0) {
      // new element
      uint size = addresses.length;
      if (size == 0xFFFF)
        throw;
      isNew = true;
      empIdx = uint16(size + 1);
      addresses.push(e);
      CreateEmployee(e, options, extraOptions, empIdx);
    } else {
      isNew = false;
      UpdateEmployee(e, options, extraOptions, empIdx);
    }
    employees[e] = Employee({
        vestingStarted: vestingStarted,
        timeToSign: timeToSign,
        terminatedAt: terminatedAt,
        fadeoutStarts: fadeoutStarts,
        options: options,
        extraOptions: extraOptions,
        state: state,
        idx: empIdx
      });
  }

  function changeState(address e, EmployeeState state)
    external
    onlyOwner
  {
    employees[e].state = state;
  }

  function removeEmployee(address e)
    external
    onlyOwner
    returns (bool)
  {
    uint16 empIdx = employees[e].idx;
    if (empIdx > 0) {
        delete employees[e];
        delete addresses[empIdx-1];
        return true;
    }
    return false;
  }

  function terminateEmployee(address e, uint32 terminatedAt, uint32 fadeoutStarts, EmployeeState state)
    external
    onlyOwner
  {
    // somehow this get reference to storage and optimizer does it with one SSTORE
    Employee storage employee = employees[e];
    employee.state = state;
    employee.terminatedAt = terminatedAt;
    employee.fadeoutStarts = fadeoutStarts;
  }

  function getEmployee(address e)
    external
    constant
    returns (uint32, uint32, uint32, uint32, uint32, uint32, EmployeeState) {
      Employee employee = employees[e];
      if (employee.idx == 0)
        throw;
      // where is struct zip/unzip :>
      return (employee.vestingStarted, employee.timeToSign, employee.terminatedAt, employee.fadeoutStarts,
        employee.options, employee.extraOptions, employee.state);
    }

   function hasEmployee(address e)
    external
    constant
    returns (bool) {
      // this is very inefficient - whole word is loaded just to check this
      return employees[e].idx != 0;
    }

  function getSerializedEmployee(address e)
    external
    constant
    returns (uint[8] emp)
  {
    Employee memory employee = employees[e];
    if (employee.idx == 0)
      throw;
    // guess what: struct layout in memory is aligned to word (256 bits)
    // struct in storage is byte aligned
    assembly {
      // return memory aligned struct as array of words
      // I just wonder when 'employee' memory is deallocated
      emp := employee
    }
  }
}

contract IOptionsConverter
{

  modifier onlyESOP() {
    if (msg.sender != getESOP())
      throw;
    _;
  }
  function getESOP() public returns (address);
  // executes conversion of options for given employee and amount
  function convertOptions(address employee, uint options) onlyESOP public;
}
