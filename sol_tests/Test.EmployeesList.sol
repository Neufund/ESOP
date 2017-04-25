pragma solidity ^0.4.8;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./EmployeesList.sol";

contract TestEmployeesList is Test, Reporter, ESOPTypes
{

  function setUp() {
  }

  function testAddRemoveEmployee() logs_gas() {
    Tester emp1 = new Tester();
    EmployeesList l = new EmployeesList();
    uint32 ct = uint32(block.timestamp);
    bool isNew = l.setEmployee(address(emp1), ct, ct + 2 weeks, ct + 3 weeks, ct + 4 weeks, 100, 200, 0, EmployeeState.Employed);
    assertEq(isNew, true);
    isNew = l.setEmployee(address(emp1), ct, ct + 2 weeks, ct + 3 weeks, ct + 4 weeks, 100, 200, 0, EmployeeState.Employed);
    assertEq(isNew, false);
    assertEq(uint(l.size()), 1);
    assertEq(l.addresses(0), address(emp1));
    bool isRem = l.removeEmployee(address(emp1));
    assertEq(isRem, true);
    assertEq(uint(l.size()), 1);
    // test internals
    assertEq(l.addresses(0), address(0));
    isRem = l.removeEmployee(address(emp1));
    assertEq(isRem, false);
  }

  function testMultiAddRemoveEmployee() logs_gas() {
    Tester emp1 = new Tester();
    EmployeesList l = new EmployeesList();
    uint32 ct = uint32(block.timestamp);
    bool isNew = l.setEmployee(address(emp1), ct, ct + 2 weeks, ct + 3 weeks, ct + 4 weeks, 100, 200, 0, EmployeeState.Employed);
    assertEq(isNew, true);
    Tester emp2 = new Tester();
    isNew = l.setEmployee(address(emp2), ct, ct + 2 weeks, ct + 3 weeks, ct + 4 weeks, 1000, 2000, 0, EmployeeState.Terminated);
    assertEq(isNew, true);
    assertEq(uint(l.size()), 2);
    assertEq(l.addresses(0), address(emp1));
    assertEq(l.hasEmployee(address(emp1)), true);
    assertEq(l.addresses(1), address(emp2));
    // test if indexes match
    Employee memory emp = deserializeEmployee(l.getSerializedEmployee(address(emp1)));
    assertEq(uint(emp.idx-1), 0, "employee 1 indexes must match");
    emp = deserializeEmployee(l.getSerializedEmployee(address(emp2)));
    assertEq(uint(emp.idx-1), 1, "employee 2 indexes must match");

    bool isRem = l.removeEmployee(address(emp2));
    assertEq(isRem, true);
    assertEq(uint(l.size()), 2);
    // test internals
    assertEq(l.addresses(0), address(emp1));
    assertEq(l.hasEmployee(address(emp1)), true);
    assertEq(l.addresses(1), address(0));
    assertEq(l.hasEmployee(address(emp2)), false);
    isRem = l.removeEmployee(address(emp1));
    assertEq(isRem, true);
    assertEq(l.addresses(0), address(0));
    assertEq(l.hasEmployee(address(emp1)), false);
    assertEq(l.addresses(1), address(0));
    assertEq(l.hasEmployee(address(emp2)), false);
    // test indexes again by adding user that was just deleted
    isNew = l.setEmployee(address(emp2), ct, ct + 2 weeks, ct + 3 weeks, ct + 4 weeks, 100, 0, 0, EmployeeState.Employed);
    assertEq(isNew, true);
    emp = deserializeEmployee(l.getSerializedEmployee(address(emp2)));
    assertEq(uint(emp.idx-1), 2, "employee 2a indexes must match");
  }

  function testPersistence() logs_gas() {
    Tester emp1 = new Tester();
    EmployeesList l = new EmployeesList();
    uint32 ct = uint32(block.timestamp);
    l.setEmployee(address(emp1), ct, ct + 2 weeks, ct + 3 weeks, ct + 4 weeks, 100, 200, 32987, EmployeeState.Employed);
    Employee memory emp = deserializeEmployee(l.getSerializedEmployee(address(emp1)));
    // now compare all fields
    assertEq(uint(emp.issueDate), uint(ct));
    assertEq(uint(emp.timeToSign), uint(ct + 2 weeks));
    assertEq(uint(emp.terminatedAt), uint(ct + 3 weeks));
    assertEq(uint(emp.fadeoutStarts), uint(ct + 4 weeks));
    assertEq(uint(emp.poolOptions), 100);
    assertEq(uint(emp.extraOptions), 200);
    assertEq(uint(emp.suspendedAt), 32987);
    assertEq(uint(emp.state), uint(EmployeeState.Employed));
    // modify
    l.terminateEmployee(address(emp1), emp.issueDate, ct + 1 years, ct + 2 years, EmployeeState.Terminated);
    emp = deserializeEmployee(l.getSerializedEmployee(address(emp1)));
    assertEq(uint(emp.terminatedAt), uint(ct + 1 years));
    assertEq(uint(emp.fadeoutStarts), uint(ct + 2 years));
    assertEq(uint(emp.state), uint(EmployeeState.Terminated));
    // change state
    l.changeState(address(emp1), EmployeeState.OptionsExercised);
    emp = deserializeEmployee(l.getSerializedEmployee(address(emp1)));
    assertEq(uint(emp.state), uint(EmployeeState.OptionsExercised));
    // direct mod
    l.setEmployee(address(emp1), ct, ct + 2 weeks, ct + 3 weeks, ct + 4 weeks, 1000, 2000, 761867, EmployeeState.Employed);
    emp = deserializeEmployee(l.getSerializedEmployee(address(emp1)));
    assertEq(uint(emp.poolOptions), 1000);
    assertEq(uint(emp.extraOptions), 2000);
    assertEq(uint(emp.suspendedAt), 761867);
    // directly write fadeout time
    l.setFadeoutStarts(address(emp1), ct + 7 weeks);
    emp = deserializeEmployee(l.getSerializedEmployee(address(emp1)));
    assertEq(uint(emp.fadeoutStarts), uint(ct + 7 weeks));
  }

  function testThrowGetNonExistingEmployee() {
    Tester emp1 = new Tester();
    EmployeesList l = new EmployeesList();
    uint32 ct = uint32(block.timestamp);
    l.setEmployee(address(emp1), ct, ct + 2 weeks, ct + 3 weeks, ct + 4 weeks, 100, 200, 0, EmployeeState.Employed);
    Tester emp2 = new Tester();
    var sere = l.getSerializedEmployee(address(emp2));

  }

  function testThrowTerminanteNonExitstingEmployee() {
    EmployeesList l = new EmployeesList();
    Tester emp2 = new Tester();
    l.terminateEmployee(address(emp2),0, 0, 0, EmployeeState.Terminated);
  }

  function testThrowTerminateWithInvalidState() {
    Tester emp1 = new Tester();
    EmployeesList l = new EmployeesList();
    uint32 ct = uint32(block.timestamp);
    l.setEmployee(address(emp1), ct, ct + 2 weeks, ct + 3 weeks, ct + 4 weeks, 100, 200, 0, EmployeeState.Employed);
    l.terminateEmployee(address(emp1), ct, 0, 0, EmployeeState.Employed);
  }

  function testThrowChangeStateNonExistingEmployee() {
    EmployeesList l = new EmployeesList();
    Tester emp2 = new Tester();
    l.changeState(address(emp2), EmployeeState.Terminated);
  }

}
