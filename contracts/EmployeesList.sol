pragma solidity ^0.4.8;
import "./ESOPTypes.sol";


contract EmployeesList is ESOPTypes, Ownable, Destructable {
  event CreateEmployee(address indexed e, uint32 poolOptions, uint32 extraOptions, uint16 idx);
  event UpdateEmployee(address indexed e, uint32 poolOptions, uint32 extraOptions, uint16 idx);
  event ChangeEmployeeState(address indexed e, EmployeeState oldState, EmployeeState newState);
  event RemoveEmployee(address indexed e);
  mapping (address => Employee) employees;
  // addresses in the mapping, ever
  address[] public addresses;

  function size() external constant returns (uint16) {
    return uint16(addresses.length);
  }

  function setEmployee(address e, uint32 issueDate, uint32 timeToSign, uint32 terminatedAt, uint32 fadeoutStarts,
    uint32 poolOptions, uint32 extraOptions, uint32 suspendedAt, EmployeeState state)
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
      CreateEmployee(e, poolOptions, extraOptions, empIdx);
    } else {
      isNew = false;
      UpdateEmployee(e, poolOptions, extraOptions, empIdx);
    }
    employees[e] = Employee({
        issueDate: issueDate,
        timeToSign: timeToSign,
        terminatedAt: terminatedAt,
        fadeoutStarts: fadeoutStarts,
        poolOptions: poolOptions,
        extraOptions: extraOptions,
        suspendedAt: suspendedAt,
        state: state,
        idx: empIdx
      });
  }

  function changeState(address e, EmployeeState state)
    external
    onlyOwner
  {
    if (employees[e].idx == 0)
      throw;
    ChangeEmployeeState(e, employees[e].state, state);
    employees[e].state = state;
  }

  function setFadeoutStarts(address e, uint32 fadeoutStarts)
    external
    onlyOwner
  {
    if (employees[e].idx == 0)
      throw;
    UpdateEmployee(e, employees[e].poolOptions, employees[e].extraOptions, employees[e].idx);
    employees[e].fadeoutStarts = fadeoutStarts;
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

  function terminateEmployee(address e, uint32 issueDate, uint32 terminatedAt, uint32 fadeoutStarts, EmployeeState state)
    external
    onlyOwner
  {
    if (state != EmployeeState.Terminated)
        throw;
    Employee employee = employees[e]; // gets reference to storage and optimizer does it with one SSTORE
    if (employee.idx == 0)
      throw;
    ChangeEmployeeState(e, employee.state, state);
    employee.state = state;
    employee.issueDate = issueDate;
    employee.terminatedAt = terminatedAt;
    employee.fadeoutStarts = fadeoutStarts;
    employee.suspendedAt = 0;
    UpdateEmployee(e, employee.poolOptions, employee.extraOptions, employee.idx);
  }

  function getEmployee(address e)
    external
    constant
    returns (uint32, uint32, uint32, uint32, uint32, uint32, uint32, EmployeeState)
  {
      Employee employee = employees[e];
      if (employee.idx == 0)
        throw;
      // where is struct zip/unzip :>
      return (employee.issueDate, employee.timeToSign, employee.terminatedAt, employee.fadeoutStarts,
        employee.poolOptions, employee.extraOptions, employee.suspendedAt, employee.state);
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
    returns (uint[9])
  {
    Employee memory employee = employees[e];
    if (employee.idx == 0)
      throw;
    return serializeEmployee(employee);
  }
}
