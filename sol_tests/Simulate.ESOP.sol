pragma solidity ^0.4.0;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import './Test.Types.sol';
import "./Test.DummyOptionConverter.sol";
import "./ESOP.sol";


contract TestESOP is Test, ESOPMaker, Reporter, ESOPTypes
{
    EmpTester emp1;
    EmpTester emp2;
    ESOP esop;

  function setUp() {
    emp1 = new EmpTester();
    emp2 = new EmpTester();
    esop = makeNFESOP();
    setupReporter('./solc/simulations.csv');
  }

  function simulateLifecycleSingleEmp(uint32 ct) {
    uint8 rc = uint8(emp1.employeeSignsToESOP());
    //@info vesting sim days `uint esop.vestingDuration()`
    uint vdays = esop.vestingDuration() / 7 days;
    //@info vesting sim weeks `uint vdays`
    uint ro;
    uint teo;
    for(uint d = 0; d < vdays + 4; d++) {
      uint dn = d*7;
      uint options = esop.calcEffectiveOptionsForEmployee(address(emp1), uint32(ct + d*(7 days)));
      ro = esop.remainingOptions(); teo = esop.totalExtraOptions();
      //@doc `uint dn`, `uint options`, `uint ro`, `uint teo`, vesting
    }
    uint fdays = vdays+4; // fadeut time == time of employment
    // terminate employee
    esop.terminateEmployee(address(emp1), uint32(ct + fdays*(7 days)), 0);
    //@info fadeout sim weeks `uint fdays`
    for(d = 1; d < fdays + 5; d++) {
      dn = d*7 + vdays*7;
      options = esop.calcEffectiveOptionsForEmployee(address(emp1), uint32(ct + (vdays+4)*7 days + d*(7 days)));
      ro = esop.remainingOptions(); teo = esop.totalExtraOptions();
      //@doc `uint dn`, `uint options`, `uint ro`, `uint teo`, fadeout
    }
    // trigger conversion event
    dn = (vdays + fdays + 5)*7;
    ct = uint32(ct + dn*1 days);
    DummyOptionsConverter converter = new DummyOptionsConverter(address(esop), ct + 2 weeks);
    esop.convertESOPOptions(ct, converter);
    options = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    ro = esop.remainingOptions(); teo = esop.totalExtraOptions();
    //@doc `uint dn`, `uint options`, `uint ro`, `uint teo`, conversion
    options = esop.calcEffectiveOptionsForEmployee(address(emp1), ct + 4 weeks);
    dn += 4*7;
    ro = esop.remainingOptions(); teo = esop.totalExtraOptions();
    //@doc `uint dn`, `uint options`, `uint ro`, `uint teo`, conversion expired
    //@doc -
    // convert options, but first manipulate time
    esop.mockTime(ct);
    rc = uint8(emp1.employeeConvertsOptions());
    //@info converted `uint8 rc` with `uint converter.totalConvertedOptions()`
  }

  function testSimulateEmployeeOnlyExtra() logs_gas() {
    uint32 ct = esop.currentTime();
    uint8 rc = uint8(esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 10000, false));
    emp1._target(esop);
    //@doc vesting until maximum and keep
    simulateLifecycleSingleEmp(ct);
  }

  function testSimulateAmounts() logs_gas() {

  }

  function testSimulateManyEmployees() logs_gas() {

  }

  function testSimulateEmployeeWithEarlyExitBonus() logs_gas() {
    uint32 ct = esop.currentTime();
    uint8 rc = uint8(esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 0, false));
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    //@info vesting sim days `uint esop.vestingDuration()`
    uint vdays = (esop.vestingDuration() - 2 years) / 7 days;
    //@info vesting sim weeks `uint vdays`
    //@doc early exit with bonus
    for(uint d = 0; d < vdays + 4; d++) {
      uint dn = d*7;
      uint options = esop.calcEffectiveOptionsForEmployee(address(emp1), uint32(ct + d*(7 days)));
      //@doc `uint dn`, `uint options`, vesting
    }
    uint fdays = vdays+4; // fadeut time == time of employment
    // trigger conversion event
    dn = (fdays)*7;
    ct = uint32(ct + dn*1 days);
    DummyOptionsConverter converter = new DummyOptionsConverter(address(esop), ct + 1 years);
    esop.convertESOPOptions(ct, converter);
    for(d = 0; d < 14; d++) {
      dn = d*7;
      options = esop.calcEffectiveOptionsForEmployee(address(emp1), uint32(ct + d*(7 days)));
      //@doc `uint dn`, `uint options`, bonus
    }
    //@doc -
    // convert options, but first manipulate time
    esop.mockTime(ct);
    emp1.employeeConvertsOptions();
    //@info converted `uint8 rc` with `uint converter.totalConvertedOptions()`
  }

  function testSimulateEmployeeWithExitBonus() logs_gas() {
    uint32 ct = esop.currentTime();
    uint8 rc = uint8(esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 0, false));
    emp1._target(esop);
    rc = emp1.employeeSignsToESOP();
    //@info vesting sim days `uint esop.vestingDuration()`
    uint vdays = (esop.vestingDuration() + 1 years) / 7 days;
    //@info vesting sim weeks `uint vdays`
    //@doc vesting until maximum then conversion with exit bonus
    for(uint d = 0; d < vdays + 4; d++) {
      uint dn = d*7;
      uint options = esop.calcEffectiveOptionsForEmployee(address(emp1), uint32(ct + d*(7 days)));
      //@doc `uint dn`, `uint options`, vesting
    }
    uint fdays = vdays+4; // fadeut time == time of employment
    // trigger conversion event
    dn = (fdays)*7;
    ct = uint32(ct + dn*1 days);
    DummyOptionsConverter converter = new DummyOptionsConverter(address(esop), ct + 1 years);
    esop.convertESOPOptions(ct, converter);
    for(d = 0; d < 14; d++) {
      dn = d*7;
      options = esop.calcEffectiveOptionsForEmployee(address(emp1), uint32(ct + d*(7 days)));
      //@doc `uint dn`, `uint options`, bonus
    }
    //@doc -
    // convert options, but first manipulate time
    esop.mockTime(ct);
    rc = uint8(emp1.employeeConvertsOptions());
    //@info converted `uint8 rc` with `uint converter.totalConvertedOptions()`
  }

  function testSimulateEmployeeOptionsWithRegTermFull() logs_gas() {
    uint32 ct = esop.currentTime();
    uint8 rc = uint8(esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 0, false));
    emp1._target(esop);
    //@doc vesting until maximum and fade out in full
    simulateLifecycleSingleEmp(ct);
  }

  function testSimulateESOPWithSimulateFunction() {
    //@doc simulate using simulate function
    uint32 ct = esop.currentTime();
    // get options for employee no 1
    uint32 empopts = uint32(esop.divRound(esop.totalOptions() * esop.newEmployeePoolPromille(), esop.FP_SCALE()));
    //@info vesting sim days `uint esop.vestingDuration()` options `uint empopts`
    uint vdays = esop.vestingDuration() / 7 days;
    for(uint d = 0; d < vdays + 4; d++) {
      uint dn = d*7;
      uint options = esop.simulateEffectiveOptionsForEmployee(ct, 0, empopts, 0, uint8(EmployeeState.Employed), uint32(ct + d*(7 days)));
      //@doc `uint dn`, `uint options`, vesting
    }
    // terminate employee
    uint32 terminatedAt = uint32(ct + (vdays+4)*(7 days));
    for(d = 1; d < (vdays+4) + 5; d++) {
      dn = d*7 + vdays*7;
      options = esop.simulateEffectiveOptionsForEmployee(ct, terminatedAt, empopts, 0, uint8(EmployeeState.Terminated), uint32(ct + (vdays+4)*7 days + d*(7 days)));
      //@doc `uint dn`, `uint options`, fadeout
    }
  }

}
