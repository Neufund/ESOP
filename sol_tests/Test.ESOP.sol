pragma solidity ^0.4.0;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "Test.DummyOptionConverter.sol";
import "./ESOP.sol";


contract EmpTester {
  address _t;
  function _target( address target ) {
    _t = target;
  }
  function() {
    if(!_t.call(msg.data)) throw;
  }

  function employeeConvertsOptions() returns (uint8){
      return uint8(ESOP(_t).employeeConvertsOptions());
  }

  function employeeSignsToESOP() returns (uint8){
      return uint8(ESOP(_t).employeeSignsToESOP());
  }
}


contract TestESOP is Test, Reporter, ESOPTypes
{
    EmpTester emp1;
    Tester emp2;
    ESOP esop;
    DummyOptionsConverter converter;

  function setUp() {
    emp1 = new EmpTester();
    emp2 = new Tester();
    esop = new ESOP();
    converter = new DummyOptionsConverter(address(esop));
  }

  function skipSerializedEmployee() logs_gas()
  {
    uint32 ct = esop.currentTime();
    uint8 rc = uint8(esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 100));
    //@info addNewEmployeeToESOP rc `uint8 rc` ct `uint32 ct`
    EmployeesList employees = esop.employees();
    // var (_, _1, _2, _3, _4, _5, state) = employees.getEmployee(address(emp1));
    //info extra `uint16 _5`
    var sere = employees.getSerializedEmployee(address(emp1));
    //@info sere `uint[8] sere`
    Employee memory emp;
    assembly {
      //mstore(emp, sere)
      emp := sere
    }
    //@info emp.vestingStarted `uint32 emp.vestingStarted`
    //@info emp.timeToSign `uint32 emp.timeToSign`
    //@info emp.extraOptions `uint32 emp.extraOptions`
    //@info emp.state `uint8 uint8(emp.state)`
  }

  function testAccess()
  {

  }

  function testSignTooLate() {

  }

  function testFadeoutToPool()
  {
    // also check if still the same options are calculated on termination
  }

  function testSignaturesExpiredToPool()
  {

  }

  function testLifecycleOptions()
  {

  }

  function testConversionStopsFadeout()
  {
    uint32 ct = esop.currentTime();
    esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 100);
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    // then after a year employee terminated regular
    ct += 1 years;
    rc = uint8(esop.terminateEmployee(emp1, ct, 0));
    assertEq(uint(rc), 0);
    // then after a month fund converts
    ct += 30 days;
    uint8 rc = uint8(esop.esopConversionEvent(ct, ct + 60 days, converter));
    assertEq(uint(rc), 0, "esopConversionEvent");
    uint optionsAtConv = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    uint optionsCv1m = esop.calcEffectiveOptionsForEmployee(address(emp1), ct + 30 days);
    //@info options diff should be 0 `uint optionsAtConv` `uint optionsCv1m`
    assertEq(optionsCv1m, optionsAtConv);

  }

  function testEmployeeConversion() logs_gas()
  {
    uint32 ct = esop.currentTime();
    esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 100);
    emp1._target(esop);
    ESOP(emp1).employeeSignsToESOP();
    // then after a year fund converts
    ct += 1 years;
    uint8 rc = uint8(esop.esopConversionEvent(ct, ct + 2 weeks, converter));
    assertEq(uint(rc), 0, "esopConversionEvent");
    // mock time
    uint32 toolate = (ct + 4 weeks);
    esop.mockTime(toolate);
    // should be too late
    //@info ct `uint32 ct` convertedAt `uint32 esop.conversionEventTime()` conv deadline `uint32 esop.employeeConversionDeadline()` too late `uint32 toolate`
    rc = emp1.employeeConvertsOptions();
    assertEq(uint(rc), 2, "employeeConvertsOptions");
    //@info `uint converter.totalConvertedOptions()` converted, should be 0
    esop.mockTime(ct + 2 weeks);
    // convert options
    rc = emp1.employeeConvertsOptions();
    assertEq(uint(rc), 0, "employeeConvertsOptions");
    // we expect all extra options + pool options + 20% exit bonus on pool options
    uint poolopts = esop.totalOptions() - esop.remainingOptions();
    uint expopts = 100 + poolopts + poolopts/5;
    // what is converted is stored in dummy so compare
    assertEq(converter.totalConvertedOptions(), expopts);
    //@info `uint expopts` converted
    // invalid emp state
    rc = emp1.employeeConvertsOptions();
    assertEq(uint(rc), 1, "employeeConvertsOptions");
    // 0 options left
    uint options = esop.calcEffectiveOptionsForEmployee(address(emp1), ct + 2 weeks);
    assertEq(options, 0);
  }

  function testEmployeeSimpleLifecycle() logs_gas()
  {
    uint32 ct = esop.currentTime();
    uint initialOptions = esop.remainingOptions();
    uint8 rc = uint8(esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 100));
    assertEq(uint(rc), 0);
    emp1._target(esop);
    rc = emp1.employeeSignsToESOP();
    assertEq(uint(rc), 0);
    // terminated for a cause
    rc = uint8(esop.terminateEmployee(emp1, ct + 3 weeks, 2));
    assertEq(uint(rc), 0);
    assertEq(initialOptions, esop.remainingOptions());
  }

  function testMockTime() {
    //@info block number `uint block.number`
    uint32 t = esop.currentTime();
    assertEq(uint(t), block.timestamp);
    esop.mockTime(t + 4 weeks);
    assertEq(uint(esop.currentTime()), t + 4 weeks);
    // set back
    esop.mockTime(0);
    assertEq(uint(esop.currentTime()), block.timestamp);
  }
}
