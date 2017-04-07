pragma solidity ^0.4.0;
import "./Types.sol";

contract ESOPTypes {
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


contract EmployeesList is ESOPTypes, Ownable {
  event CreateEmployee(address indexed e, uint32 options, uint32 extraOptions, uint16 idx);
  event UpdateEmployee(address indexed e, uint32 options, uint32 extraOptions, uint16 idx);
  event ChangeEmployeeState(address indexed e, EmployeeState oldState, EmployeeState newState);
  event RemoveEmployee(address indexed e);
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
    if (employees[e].idx == 0) throw;
    ChangeEmployeeState(e, employees[e].state, state);
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
        RemoveEmployee(e);
        return true;
    }
    return false;
  }

  function terminateEmployee(address e, uint32 terminatedAt, uint32 fadeoutStarts, EmployeeState state)
    external
    onlyOwner
  {
    if (state != EmployeeState.Terminated && state != EmployeeState.GoodWillTerminated)
        throw;
    Employee employee = employees[e]; // gets reference to storage and optimizer does it with one SSTORE
    if (employee.idx == 0) throw;
    ChangeEmployeeState(e, employee.state, state);
    employee.state = state;
    employee.terminatedAt = terminatedAt;
    employee.fadeoutStarts = fadeoutStarts;
    UpdateEmployee(e, employee.options, employee.extraOptions, employee.idx);
  }

  function getEmployee(address e)
    external
    constant
    returns (uint32, uint32, uint32, uint32, uint32, uint32, EmployeeState)
  {
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
     returns (bool)
   {
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
      // answer: memory is not deallocated until transaction ends
      emp := employee
    }
  }
}


contract IOptionsConverter {

  // modifiers are inherited, check `owned` pattern
  //   http://solidity.readthedocs.io/en/develop/contracts.html#function-modifiers
  modifier onlyESOP() {
    if (msg.sender != getESOP())
      throw;
    _;
  }
  function getESOP() public constant returns (address);
  function getConversionDeadline() public constant returns (uint32);

  // executes conversion of options for given employee and amount
  function convertOptions(address employee, uint options) onlyESOP public;
}
