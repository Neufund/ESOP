pragma solidity ^0.4.8;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import './Test.Types.sol';
import "./Test.DummyOptionConverter.sol";
import "./ESOP.sol";


contract TestESOP is Test, ESOPMaker, Reporter, ESOPTypes, Math
{
    EmpTester emp1;
    EmpTester emp2;
    ESOP esop;
    uint32 globct;

  function setUp() {
    emp1 = new EmpTester();
    emp2 = new EmpTester();
    esop = makeNFESOP();
    globct = esop.currentTime();
    setupReporter('./solc/simulations.csv');
  }

  function simulateLifecycleSingleEmp(uint32 ct) {
    uint8 rc = uint8(emp1.employeeSignsToESOP());
    //@info vesting sim days `uint esop.optionsCalculator().vestingPeriod()`
    uint vdays = esop.optionsCalculator().vestingPeriod() / 7 days;
    //@info vesting sim weeks `uint vdays`
    uint ro;
    uint teo;
    for(uint d = 0; d < vdays + 4; d++) {
      uint dn = d*7;
      uint options = esop.calcEffectiveOptionsForEmployee(address(emp1), uint32(ct + d*(7 days)));
      ro = esop.remainingPoolOptions(); teo = esop.totalExtraOptions();
      //@doc `uint dn`, `uint options`, `uint ro`, `uint teo`, vesting
    }
    uint fdays = vdays+4; // fadeut time == time of employment
    // terminate employee
    esop.terminateEmployee(address(emp1), uint32(ct + fdays*(7 days)), 0);
    //@info fadeout sim weeks `uint fdays`
    for(d = 1; d < fdays + 5; d++) {
      dn = d*7 + vdays*7;
      options = esop.calcEffectiveOptionsForEmployee(address(emp1), uint32(ct + (vdays+4)*7 days + d*(7 days)));
      ro = esop.remainingPoolOptions(); teo = esop.totalExtraOptions();
      //@doc `uint dn`, `uint options`, `uint ro`, `uint teo`, fadeout
    }
    // trigger conversion event
    dn = (vdays + fdays + 5)*7;
    ct = uint32(ct + dn*1 days);
    DummyOptionsConverter converter = new DummyOptionsConverter(address(esop), ct + 2 weeks);
    esop.mockTime(ct);
    esop.offerOptionsConversion(converter);
    options = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    ro = esop.remainingPoolOptions(); teo = esop.totalExtraOptions();
    //@doc `uint dn`, `uint options`, `uint ro`, `uint teo`, conversion
    options = esop.calcEffectiveOptionsForEmployee(address(emp1), ct + 4 weeks);
    dn += 4*7;
    ro = esop.remainingPoolOptions(); teo = esop.totalExtraOptions();
    //@doc `uint dn`, `uint options`, `uint ro`, `uint teo`, conversion expired
    //@doc -
    // convert options, but first manipulate time
    esop.mockTime(ct);
    rc = uint8(emp1.employeeExerciseOptions(true));
    //@info converted `uint8 rc` with `uint converter.totalConvertedOptions()`
  }

  function testSimulateEmployeeOnlyExtra() logs_gas() {
    uint32 ct = esop.currentTime();
    uint8 rc = uint8(esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 10000, false));
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
    uint8 rc = uint8(esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false));
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    //@info vesting sim days `uint esop.optionsCalculator().vestingPeriod()`
    uint vdays = (esop.optionsCalculator().vestingPeriod() - 2 years) / 7 days;
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
    esop.mockTime(ct);
    esop.offerOptionsConversion(converter);
    for(d = 0; d < 14; d++) {
      dn = d*7;
      options = esop.calcEffectiveOptionsForEmployee(address(emp1), uint32(ct + d*(7 days)));
      //@doc `uint dn`, `uint options`, bonus
    }
    //@doc -
    // convert options, but first manipulate time
    esop.mockTime(ct);
    emp1.employeeExerciseOptions(true);
    //@info converted `uint8 rc` with `uint converter.totalConvertedOptions()`
  }

  function testSimulateEmployeeWithExitBonus() logs_gas() {
    uint32 ct = esop.currentTime();
    uint8 rc = uint8(esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false));
    emp1._target(esop);
    rc = emp1.employeeSignsToESOP();
    //@info vesting sim days `uint esop.optionsCalculator().vestingPeriod()`
    uint vdays = (esop.optionsCalculator().vestingPeriod() + 1 years) / 7 days;
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
    esop.mockTime(ct);
    esop.offerOptionsConversion(converter);
    for(d = 0; d < 14; d++) {
      dn = d*7;
      options = esop.calcEffectiveOptionsForEmployee(address(emp1), uint32(ct + d*(7 days)));
      //@doc `uint dn`, `uint options`, bonus
    }
    //@doc -
    // convert options, but first manipulate time
    esop.mockTime(ct);
    rc = uint8(emp1.employeeExerciseOptions(true));
    //@info converted `uint8 rc` with `uint converter.totalConvertedOptions()`
  }

  function testSimulateEmployeeOptionsWithRegTermFull() logs_gas() {
    uint32 ct = esop.currentTime();
    uint8 rc = uint8(esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false));
    emp1._target(esop);
    //@doc vesting until maximum and fade out in full
    simulateLifecycleSingleEmp(ct);
  }

  function testSimulateESOPWithSimulateFunction() {
    uint vdays = esop.optionsCalculator().vestingPeriod() / 7 days;
    uint32 terminatedAt = uint32(globct + (vdays+4)*(7 days));
    //@doc simulate using simulate function
    uint32 empopts = uint32(divRound(esop.totalPoolOptions() * esop.optionsCalculator().newEmployeePoolPromille(), esop.optionsCalculator().FP_SCALE()));

    for(uint d = 0; d < vdays + 4; d++) {
      uint dn = d*7;
      uint options = esop.optionsCalculator().simulateOptions(globct, 0, empopts, 0, 0,
        uint8(EmployeeState.Employed), uint32(globct + d*(7 days)));
      //@doc `uint dn`, `uint options`, vesting
    }
    for(d = 1; d < (vdays+4) + 5; d++) {
      dn = d*7 + vdays*7;
      options = esop.optionsCalculator().simulateOptions(globct, terminatedAt, empopts, 0, 0,
        uint8(EmployeeState.Terminated), uint32(globct + (vdays+4)*7 days + d*(7 days)));
      //@doc `uint dn`, `uint options`, fadeout
    }
  }
}
