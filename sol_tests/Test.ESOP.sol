pragma solidity ^0.4.0;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.DummyOptionConverter.sol";
import "./Test.Types.sol";

contract TestESOP is Test, ESOPMaker, Reporter, ESOPTypes, Math
{
    EmpTester emp1;
    Tester emp2;
    ESOP esop;
    DummyOptionsConverter converter;

  function setUp() {
    emp1 = new EmpTester();
    emp2 = new Tester();
    esop = makeNFESOP();
  }

  function testSignTooLate() {

  }

  function testUnsupportedFork() logs_gas {
    // company can kill on unsupported fork
    root.killOnUnsupportedFork();
    // suicide will not work until block is mined
    // todo: integration test
    assertEq(root.ESOPAddress(), address(0));
  }

  function testThrowTerminationBadLeaver() {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false);
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    ct += uint32(esop.vestingPeriod() / 2);
    esop.mockTime(ct);
    // terminate bad leaver
    uint8 rc = uint8(esop.terminateEmployee(emp1, ct, 1));
    assertEq(uint(rc), 0);
    // this throws - user does not exist anymore
    uint options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
  }

  function testThrowTerminationWhenNotSigned() {
    // test termination upgrade to bad leaver when not signed in time
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false);
    emp1._target(esop);
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    ct += uint32(esop.vestingPeriod() / 2);
    esop.mockTime(ct);
    // terminate will upgrade to term bad leaver when no signature
    uint8 rc = uint8(esop.terminateEmployee(emp1, ct, 0));
    assertEq(uint(rc), 0);
    // this throws - user does not exist anymore
    uint options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
  }

  function testOptionsBeforeAndAfterTermination() {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false);
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    ct += uint32(esop.vestingPeriod() / 2);
    esop.mockTime(ct);
    uint8 rc = uint8(esop.terminateEmployee(emp1, ct, 0));
    assertEq(uint(rc), 0);
    // options before termination as expected (termination in the future)
    uint options = esop.calcEffectiveOptionsForEmployee(emp1, ct -1);
    assertEq(options, divRound(maxopts, 2), "sec bef term");
    // options after termination as expected
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct +1);
    assertEq(options, divRound(maxopts, 2), "sec after term");
    ct -= uint32(esop.vestingPeriod() / 4);
    esop.mockTime(ct);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(maxopts, 4), "half bef term");
  }

  function testSuspendEmployee() {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false);
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    // suspend after 2 years
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    ct += uint32(esop.vestingPeriod() / 2);
    esop.mockTime(ct);
    uint8 rc = uint8(esop.suspendEmployee(emp1, ct));
    assertEq(uint(rc), 0);
    // when suspended value after 2 years is kept
    uint options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(maxopts, 2), "on suspension");
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct - uint32(esop.vestingPeriod() / 8));
    assertEq(options, divRound(3 * maxopts, 8), "before suspension");
    ct += uint32(esop.vestingPeriod() / 4);
    esop.mockTime(ct);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(maxopts, 2), "on suspension + 1y");
    // continue employment
    rc = uint8(esop.continueSuspendedEmployee(emp1, ct));
    assertEq(uint(rc), 0);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(maxopts, 2), "continue");
    ct += uint32(esop.vestingPeriod() / 4);
    esop.mockTime(ct);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(3 * maxopts, 4), "continue + 1y");
    // suspend again
    rc = uint8(esop.suspendEmployee(emp1, ct));
    assertEq(uint(rc), 0);
    ct += uint32(esop.vestingPeriod() / 4);
    esop.mockTime(ct);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(3 * maxopts, 4), "2 susp + 1y");
    // terminate
    rc = uint8(esop.terminateEmployee(emp1, ct, 0));
    assertEq(uint(rc), 0);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(3 * maxopts, 4), "2 susp + term");
    // suspended before termination
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct - uint32(esop.vestingPeriod() / 8));
    assertEq(options, divRound(5 * maxopts, 8), "2 susp + term + before");
    // term is term
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct + uint32(esop.vestingPeriod() / 8));
    assertEq(options, divRound(3 * maxopts, 4), "2 susp + term + after");
  }

  function testTerminationOnConversion() {
    // this tests use case when employee does not want to work for acquirer and gets no bonus
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 10000, false);
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions() + 10000;
    ct += uint32(esop.vestingPeriod() / 2);
    esop.mockTime(ct);
    // terminate employee
    rc = uint8(esop.terminateEmployee(emp1, ct, 0));
    assertEq(uint(rc), 0);
    // and convert at the same time
    converter = new DummyOptionsConverter(address(esop), ct + 60 days);
    uint8 rc = uint8(esop.offerOptionsConversion(ct, converter));
    assertEq(uint(rc), 0, "offerOptionsConversion");
    uint optionsAtConv = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    // should have optons without bonus
    assertEq(optionsAtConv, maxopts / 2, "no bonus on conv");
    // still no bonus
    optionsAtConv = esop.calcEffectiveOptionsForEmployee(address(emp1), ct + 1 weeks);
    assertEq(optionsAtConv, maxopts / 2, "no bonus week later");
    // convert and still no bonus
    emp1.employeeExerciseOptions();
    assertEq(converter.totalConvertedOptions(), maxopts / 2, "still no bonus");
  }

  function testOptionsBeforeEmploymentStarted() {
    // when someone computes options before employee was even employed
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 10000, false);
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    uint options = esop.calcEffectiveOptionsForEmployee(emp1, ct -1);
    assertEq(options, 0);
  }

  function testWhenConvertedCalcOptionsBeforeConversion() {
    // after conversion event happens, time travel before and check options
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 10000, false);
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions() + 10000;
    ct += uint32(esop.vestingPeriod() / 2);
    esop.mockTime(ct);
    converter = new DummyOptionsConverter(address(esop), ct + 60 days);
    uint8 rc = uint8(esop.offerOptionsConversion(ct, converter));
    assertEq(uint(rc), 0, "offerOptionsConversion");
    // ask just before conversion
    uint optionsAtConv = esop.calcEffectiveOptionsForEmployee(address(emp1), ct - 1);
    // should have vested options
    assertEq(optionsAtConv, maxopts / 2, "vested still");
  }

  function testConversionStopsFadeout() {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 100, false);
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    // then after a year employee terminated regular
    ct += 1 years;
    esop.mockTime(ct);
    rc = uint8(esop.terminateEmployee(emp1, ct, 0));
    assertEq(uint(rc), 0);
    // then after a month fund converts
    ct += 30 days;
    esop.mockTime(ct);
    converter = new DummyOptionsConverter(address(esop), ct + 60 days);
    uint8 rc = uint8(esop.offerOptionsConversion(ct, converter));
    assertEq(uint(rc), 0, "offerOptionsConversion");
    uint optionsAtConv = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    uint optionsCv1m = esop.calcEffectiveOptionsForEmployee(address(emp1), ct + 30 days);
    //@info options diff should be 0 `uint optionsAtConv` `uint optionsCv1m`
    assertEq(optionsCv1m, optionsAtConv);
  }

  function testEmployeeConversion() logs_gas() {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 100, false);
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    // then after a year fund converts
    ct += 1 years;
    esop.mockTime(ct);
    converter = new DummyOptionsConverter(address(esop), ct + 2 weeks);
    uint8 rc = uint8(esop.offerOptionsConversion(ct, converter));
    assertEq(uint(rc), 0, "offerOptionsConversion");
    // get emp1 employee
    Employee memory emp;
    var sere = esop.employees().getSerializedEmployee(emp1);
    assembly { emp := sere }
    //@info ct `uint32 ct` timetosign `uint32 emp.timeToSign`
    // mock time
    uint32 toolate = (ct + 4 weeks);
    esop.mockTime(toolate);
    // should be too late
    //@info ct `uint32 ct` convertedAt `uint32 esop.conversionOfferedAt()` conv deadline `uint32 esop.exerciseOptionsDeadline()` too late `uint32 toolate`
    rc = emp1.employeeExerciseOptions();
    assertEq(uint(rc), 2, "employeeExerciseOptions too late");
    //@info `uint converter.totalConvertedOptions()` converted, should be 0
    esop.mockTime(ct + 2 weeks);
    // convert options
    rc = emp1.employeeExerciseOptions();
    assertEq(uint(rc), 0, "employeeExerciseOptions");
    // we expect all extra options + pool options + 20% exit bonus on pool options
    uint poolopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    uint expopts = 100 + poolopts + divRound(poolopts * esop.bonusOptionsPromille(), esop.FP_SCALE());
    // what is converted is stored in dummy so compare
    assertEq(converter.totalConvertedOptions(), expopts);
    //@info `uint expopts` converted
    // invalid emp state
    rc = emp1.employeeExerciseOptions();
    assertEq(uint(rc), 1, "already converted");
    // 0 options left
    uint options = esop.calcEffectiveOptionsForEmployee(address(emp1), ct + 2 weeks);
    assertEq(options, 0);
  }

  function testEmployeeSimpleLifecycle() logs_gas() {
    uint32 ct = esop.currentTime();
    uint initialOptions = esop.remainingPoolOptions();
    uint8 rc = uint8(esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 100, false));
    assertEq(uint(rc), 0);
    emp1._target(esop);
    rc = emp1.employeeSignsToESOP();
    assertEq(uint(rc), 0);
    // terminated bad leaver
    esop.mockTime(ct + 3 weeks);
    rc = uint8(esop.terminateEmployee(emp1, ct + 3 weeks, 1));
    assertEq(uint(rc), 0);
    assertEq(initialOptions, esop.remainingPoolOptions());
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
