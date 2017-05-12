pragma solidity ^0.4.8;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.DummyOptionConverter.sol";
import "./Test.Types.sol";

contract TestESOP is Test, ESOPMaker, Reporter, ESOPTypes, Math
{
    EmpTester emp1;
    ESOP esop;
    DummyOptionsConverter converter;

  function setUp() {
    emp1 = new EmpTester();
    esop = makeNFESOP();
    emp1._target(esop);
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
    emp1.employeeSignsToESOP();
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 2);
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
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 2);
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
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 2);
    esop.mockTime(ct);
    uint8 rc = uint8(esop.terminateEmployee(emp1, ct, 0));
    assertEq(uint(rc), 0);
    // options before termination as expected (termination in the future)
    uint options = esop.calcEffectiveOptionsForEmployee(emp1, ct -1);
    assertEq(options, divRound(maxopts, 2), "sec bef term");
    // options after termination as expected
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct +1);
    assertEq(options, divRound(maxopts, 2), "sec after term");
    ct -= uint32(esop.optionsCalculator().vestingPeriod() / 4);
    esop.mockTime(ct);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(maxopts, 4), "half bef term");
  }

  function testSuspendEmployee() {
    uint32 ct = esop.currentTime();
    uint32 issueDate = ct;
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false);
    emp1.employeeSignsToESOP();
    // suspend after 2 years
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 2);
    esop.mockTime(ct);
    uint8 rc = uint8(esop.toggleEmployeeSuspension(emp1, ct));
    assertEq(uint(rc), 0);
    // when suspended value after 2 years is kept
    uint options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(maxopts, 2), "on suspension");
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct - uint32(esop.optionsCalculator().vestingPeriod() / 8));
    assertEq(options, divRound(3 * maxopts, 8), "before suspension");
    uint32 suspensionPeriod = uint32(esop.optionsCalculator().vestingPeriod() / 4);
    ct += suspensionPeriod;
    esop.mockTime(ct);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(maxopts, 2), "on suspension + 1y");
    // continue employment
    rc = uint8(esop.toggleEmployeeSuspension(emp1, ct));
    assertEq(uint(rc), 0);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(maxopts, 2), "continue");
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 4);
    esop.mockTime(ct);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(3 * maxopts, 4), "continue + 1y");
    // suspend again
    rc = uint8(esop.toggleEmployeeSuspension(emp1, ct));
    assertEq(uint(rc), 0);
    ct += suspensionPeriod;
    esop.mockTime(ct);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(3 * maxopts, 4), "2 susp + 1y");
    // terminate
    rc = uint8(esop.terminateEmployee(emp1, ct, 0));
    assertEq(uint(rc), 0);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct);
    //@info options on term `uint options` term_t `uint32 ct` issue_t `uint32 issueDate`
    assertEq(options, divRound(3 * maxopts, 4), "2 susp + term");
    // suspended after term with normal fadeout, check issueDate mod below!
    uint fadeout = esop.optionsCalculator().applyFadeoutToOptions(ct + uint32(esop.optionsCalculator().vestingPeriod() / 8),
      issueDate + 2*suspensionPeriod, ct, maxopts, options);
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct + uint32(esop.optionsCalculator().vestingPeriod() / 8));
    assertEq(options, fadeout, "2 susp + term + fadeout");
    // suspended before termination
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct - uint32(esop.optionsCalculator().vestingPeriod() / 8));
    assertEq(options, divRound(5 * maxopts, 8), "2 susp + term + before");
    // exercise options at termination time with 1 year exercise period
    DummyOptionsConverter converter = new DummyOptionsConverter(esop, ct + 1 years);
    rc = uint8(esop.offerOptionsConversion(converter));
    assertEq(uint(rc), 0, "converter");
    // no fadeout - keep options
    options = esop.calcEffectiveOptionsForEmployee(emp1, ct + uint32(esop.optionsCalculator().vestingPeriod() / 8));
    assertEq(options, divRound(3 * maxopts, 4), "2 susp + term + conv + after");
  }

  function procConversionStopsSuspended(bool accelVesting) {
    uint32 ct = esop.currentTime();
    uint32 issueDate = ct;
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 891721, false);
    emp1.employeeSignsToESOP();
    // suspend after 2 years
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 2);
    esop.mockTime(ct);
    uint rc = uint(esop.toggleEmployeeSuspension(emp1, ct));
    assertEq(uint(rc), 0);
    // when suspended value after 2 years is kept
    uint32 suspensionPeriod = uint32(esop.optionsCalculator().vestingPeriod() / 4);
    ct += suspensionPeriod;
    esop.mockTime(ct);
    // conversion event during suspension
    DummyOptionsConverter converter = new DummyOptionsConverter(esop, ct + 4 weeks);
    // options offered in half of the vesting
    rc = uint(esop.offerOptionsConversion(converter));
    assertEq(rc, 0, "converter");
    // agrees to accel vesting
    rc = uint(emp1.employeeExerciseOptions(accelVesting));
    assertEq(rc, 0, "exercise accelv");
    // no accel vesting then divisor is 2 -> employee was suspended hald of the vesting
    uint divisor = accelVesting ? 1 : 2;
    var (e1pool, e1extra, e1bonus, e1accel) = converter.getShare(address(emp1));
    assertEq(e1pool, divRound(maxopts, divisor), "e1pool");
    assertEq(e1extra, divRound(891721, divisor), "e1extra");
    uint bonus = accelVesting ? divRound(maxopts*esop.optionsCalculator().bonusOptionsPromille(), esop.optionsCalculator().FP_SCALE()) : 0;
    assertEq(e1bonus, bonus, "e1bonus");
    assertEq(accelVesting, e1accel, 'e1accel');
  }

  function testConversionStopsSuspendedAccel() {
    procConversionStopsSuspended(true);
  }

  function testConversionStopsSuspendedNoAccel() {
    procConversionStopsSuspended(false);
  }

  function testTerminationOnConversion() {
    // this tests use case when employee does not want to work for acquirer and gets no bonus
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 10000, false);
    emp1.employeeSignsToESOP();
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions() + 10000;
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 2);
    esop.mockTime(ct);
    // terminate employee
    rc = uint8(esop.terminateEmployee(emp1, ct, 0));
    assertEq(uint(rc), 0);
    // and convert at the same time
    converter = new DummyOptionsConverter(address(esop), ct + 60 days);
    uint8 rc = uint8(esop.offerOptionsConversion(converter));
    assertEq(uint(rc), 0, "offerOptionsConversion");
    uint optionsAtConv = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    // should have optons without bonus
    assertEq(optionsAtConv, maxopts / 2, "no bonus on conv");
    // still no bonus
    optionsAtConv = esop.calcEffectiveOptionsForEmployee(address(emp1), ct + 1 weeks);
    assertEq(optionsAtConv, maxopts / 2, "no bonus week later");
    // convert and still no bonus
    emp1.employeeExerciseOptions(true);
    assertEq(converter.totalConvertedOptions(), maxopts / 2, "still no bonus");
  }

  function testOptionsBeforeEmploymentStarted() {
    // when someone computes options before employee was even employed
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 10000, false);
    emp1.employeeSignsToESOP();
    uint options = esop.calcEffectiveOptionsForEmployee(emp1, ct -1);
    assertEq(options, 0);
  }

  function testWhenConvertedCalcOptionsBeforeConversion() {
    // after conversion event happens, time travel before and check options
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 10000, false);
    emp1.employeeSignsToESOP();
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions() + 10000;
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 2);
    esop.mockTime(ct);
    converter = new DummyOptionsConverter(address(esop), ct + 60 days);
    uint8 rc = uint8(esop.offerOptionsConversion(converter));
    assertEq(uint(rc), 0, "offerOptionsConversion");
    // ask just before conversion
    uint optionsAtConv = esop.calcEffectiveOptionsForEmployee(address(emp1), ct - 1);
    // should have vested options
    assertEq(optionsAtConv, maxopts / 2, "vested still");
  }

  function conversionFreezesOptions(bool terminate, bool exercise) {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 100, false);
    emp1.employeeSignsToESOP();
    // then after a year employee terminated regular
    ct += uint32(3 * esop.optionsCalculator().vestingPeriod() / 4);
    esop.mockTime(ct);
    if (terminate)
      rc = uint8(esop.terminateEmployee(emp1, ct, 0));
    assertEq(uint(rc), 0);
    uint optsOnTerm = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    // then after a year fund converts
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 4);
    esop.mockTime(ct);
    converter = new DummyOptionsConverter(address(esop), ct + 1 years);
    uint8 rc = uint8(esop.offerOptionsConversion(converter));
    assertEq(uint(rc), 0, "offerOptionsConversion");
    // get options directly from calculator so accel vesting can be disabled
    var sere = esop.employees().getSerializedEmployee(address(emp1));
    uint optionsAtConv = esop.optionsCalculator().calculateOptions(sere, ct, esop.conversionOfferedAt(), true);
    // opts on term should be different
    if (terminate && esop.optionsCalculator().residualAmountPromille() >= 3 * esop.optionsCalculator().FP_SCALE() / 4) {
      //@warn this test must have residual amount < 75
      return;
    } else if (optsOnTerm == optionsAtConv) {
      //@warn fadeout is not applied `uint optsOnTerm` == `uint optionsAtConv`
      fail();
    }
    uint optionsCv1y;
    if (exercise) {
      esop.mockTime(ct + 1 years);
      rc = uint8(emp1.employeeExerciseOptions(false));
      assertEq(uint(rc), 0, "opt exercise");
      optionsCv1y = converter.totalConvertedOptions();
    } else {
      optionsCv1y = esop.optionsCalculator().calculateOptions(sere, ct + 1 years, esop.conversionOfferedAt(), true);
    }
    //@info options diff should be 0 `uint optionsAtConv` `uint optionsCv1y`
    assertEq(optionsCv1y, optionsAtConv);
  }

  function testConversionStopsFadeout() {
    conversionFreezesOptions(true, false);
  }

  function testConversionStopsVestingOfTerminated() {
    conversionFreezesOptions(true, true);
  }

  function testConversionStopsVesting() {
    conversionFreezesOptions(false, true);
  }

  function testNonAcceleratedOptionsConversion() {
    EmpTester emp2 = new EmpTester();
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 1289, false);
    uint emp1issued = esop.totalPoolOptions() - esop.remainingPoolOptions();
    esop.offerOptionsToEmployee(emp2, ct, ct + 2 weeks, 7788, false);
    uint emp2issued = esop.totalPoolOptions() - esop.remainingPoolOptions() - emp1issued;
    emp2._target(esop);
    emp1.employeeSignsToESOP();
    emp2.employeeSignsToESOP();
    uint32 vestp = uint32(esop.optionsCalculator().vestingPeriod());
    esop.mockTime(ct + vestp / 2);
    uint32 deadlineDelta = vestp / 2 + 4 weeks;
    DummyOptionsConverter converter = new DummyOptionsConverter(esop, ct + deadlineDelta);
    // options offered in half of the vesting
    uint rc = uint(esop.offerOptionsConversion(converter));
    assertEq(rc, 0, "converter");
    // agrees to accel vesting
    rc = uint(emp1.employeeExerciseOptions(true));
    assertEq(rc, 0, "exercise accelv");
    var (e1pool, e1extra, e1bonus, e1accel) = converter.getShare(address(emp1));
    assertEq(e1pool, emp1issued, "e1pool");
    assertEq(e1extra, 1289, "e1extra");
    assertEq(e1bonus, divRound(emp1issued*esop.optionsCalculator().bonusOptionsPromille(), esop.optionsCalculator().FP_SCALE()), "e1bonus");
    assertEq(true, e1accel, 'e1accel');
    // does not agree
    rc = uint(emp2.employeeExerciseOptions(false));
    assertEq(rc, 0, "exercise no accelv");
    (e1pool, e1extra, e1bonus, e1accel) = converter.getShare(address(emp2));
    assertEq(e1pool, divRound(emp2issued,2), "e2pool");
    assertEq(e1extra, divRound(7788, 2), "e2extra");
    assertEq(e1bonus, 0, "e2bonus");
    assertEq(false, e1accel, 'e2accel');
  }

  function testEmployeeDeniesToExerciseOptions() {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 1289, false);
    uint emp1issued = esop.totalPoolOptions() - esop.remainingPoolOptions();
    emp1.employeeSignsToESOP();
    uint32 vestp = uint32(esop.optionsCalculator().vestingPeriod());
    esop.mockTime(ct + vestp / 2);
    uint32 deadlineDelta = vestp / 2 + 4 weeks;
    DummyOptionsConverter converter = new DummyOptionsConverter(esop, ct + deadlineDelta);
    // options offered in half of the vesting
    uint rc = uint(esop.offerOptionsConversion(converter));
    assertEq(rc, 0, "converter");
    // agrees to accel vesting
    rc = uint(emp1.employeeDenyExerciseOptions());
    assertEq(rc, 0, "deny exercise");
    var (e1pool, e1extra, e1bonus, e1accel) = converter.getShare(address(emp1));
    assertEq(e1pool, 0, "e1pool");
    assertEq(e1extra, 0, "e1extra");
    assertEq(e1bonus, 0, "e1bonus");
    assertEq(e1accel, false, 'e1accel');
    // try again as employee
    rc = uint(emp1.employeeExerciseOptions(true));
    assertEq(rc, 1, "exercise 2");
    // deny again as employee
    rc = uint(emp1.employeeDenyExerciseOptions());
    assertEq(rc, 1, "deny 2");
    // should have 0 options
    assertEq(esop.calcEffectiveOptionsForEmployee(emp1, ct + vestp / 2), 0);
  }

  function testExpiredOptionsConversion() {
    EmpTester emp2 = new EmpTester();
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 1289, false);
    uint emp1issued = esop.totalPoolOptions() - esop.remainingPoolOptions();
    esop.offerOptionsToEmployee(emp2, ct, ct + 2 weeks, 7788, false);
    uint emp2issued = esop.totalPoolOptions() - esop.remainingPoolOptions() - emp1issued;
    emp2._target(esop);
    emp1.employeeSignsToESOP();
    emp2.employeeSignsToESOP();
    uint32 vestp = uint32(esop.optionsCalculator().vestingPeriod());
    esop.mockTime(ct + vestp / 2);
    uint32 deadlineDelta = vestp / 2 + 4 weeks;
    DummyOptionsConverter converter = new DummyOptionsConverter(esop, ct + deadlineDelta);
    // options offered in half of the vesting
    uint rc = uint(esop.offerOptionsConversion(converter));
    assertEq(rc, 0, "converter");
    // try before deadline
    rc = uint(esop.exerciseExpiredEmployeeOptions(emp1, true));
    assertEq(rc, 4, "exercise accelv too early");
    esop.mockTime(ct + deadlineDelta + 1);
    // converts with accelerated vesting (when employee not notified)
    rc = uint(esop.exerciseExpiredEmployeeOptions(emp1, false));
    assertEq(rc, 0, "exercise accelv");
    var (e1pool, e1extra, e1bonus, e1accel) = converter.getShare(address(this));
    assertEq(e1pool, emp1issued, "e1pool");
    assertEq(e1extra, 1289, "e1extra");
    assertEq(e1bonus, divRound(emp1issued*esop.optionsCalculator().bonusOptionsPromille(), esop.optionsCalculator().FP_SCALE()), "e1bonus");
    assertEq(true, e1accel, 'e1accel');
    // company may convert employees that didn't do it
    rc = uint(esop.exerciseExpiredEmployeeOptions(emp2, true));
    assertEq(rc, 0, "exercise no accelv");
    // this will overwrite previous company record
    (e1pool, e1extra, e1bonus, e1accel) = converter.getShare(address(this));
    assertEq(e1pool, divRound(emp2issued,2), "e2pool");
    assertEq(e1extra, divRound(7788, 2), "e2extra");
    assertEq(e1bonus, 0, "e2bonus");
    assertEq(false, e1accel, 'e2accel');
    // try again as company
    rc = uint(esop.exerciseExpiredEmployeeOptions(emp1, true));
    assertEq(rc, 1, "exercise accelv again");
    // try again as employee
    rc = uint(emp1.employeeExerciseOptions(true));
    assertEq(rc, 2, "exercise accelv");
  }

  function testEmployeeConversion() logs_gas() {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 100, false);
    emp1.employeeSignsToESOP();
    // then after a year fund converts
    ct += 1 years;
    esop.mockTime(ct);
    converter = new DummyOptionsConverter(address(esop), ct + 2 weeks);
    uint8 rc = uint8(esop.offerOptionsConversion(converter));
    assertEq(uint(rc), 0, "offerOptionsConversion");
    // get emp1 employee
    Employee memory emp = deserializeEmployee(esop.employees().getSerializedEmployee(address(emp1)));
    //@info ct `uint32 ct` timetosign `uint32 emp.timeToSign`
    // mock time
    uint32 toolate = (ct + 4 weeks);
    esop.mockTime(toolate);
    // should be too late
    //@info ct `uint32 ct` convertedAt `uint32 esop.conversionOfferedAt()` conv deadline `uint32 esop.exerciseOptionsDeadline()` too late `uint32 toolate`
    rc = emp1.employeeExerciseOptions(true);
    assertEq(uint(rc), 2, "employeeExerciseOptions too late");
    //@info `uint converter.totalConvertedOptions()` converted, should be 0
    esop.mockTime(ct + 2 weeks);
    // convert options
    rc = emp1.employeeExerciseOptions(true);
    assertEq(uint(rc), 0, "employeeExerciseOptions");
    // we expect all extra options + pool options + 20% exit bonus on pool options
    uint poolopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    uint expopts = 100 + poolopts + divRound(poolopts * esop.optionsCalculator().bonusOptionsPromille(), esop.optionsCalculator().FP_SCALE());
    // what is converted is stored in dummy so compare
    assertEq(converter.totalConvertedOptions(), expopts);
    //@info `uint expopts` converted
    // invalid emp state
    rc = emp1.employeeExerciseOptions(true);
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
    rc = emp1.employeeSignsToESOP();
    assertEq(uint(rc), 0);
    // terminated bad leaver
    esop.mockTime(ct + 3 weeks);
    rc = uint8(esop.terminateEmployee(emp1, ct + 3 weeks, 1));
    assertEq(uint(rc), 0);
    assertEq(initialOptions, esop.remainingPoolOptions());
  }

  function testCodeUpdateCancel() {
    esop.beginCodeUpdate();
    esop.cancelCodeUpdate();
    // should be able to call normally
    uint32 ct = esop.currentTime();
    // will throw
    uint rc = uint(esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false));
    assertEq(rc, 0);
  }

  function testThrowOnCodeUpdate() {
    // business logic should be prohibited form execution, except constant methods
    esop.beginCodeUpdate();
    uint32 ct = esop.currentTime();
    // will throw
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false);
  }

  function testSignTooLate() {
    uint32 ct = esop.currentTime();
    uint rc = uint(esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false));
    assertEq(rc, 0);
    esop.mockTime(ct);
    ct += 2 weeks;
    // should sign OK on deadline
    rc = emp1.employeeSignsToESOP();
    assertEq(rc, 0, "on deadline");
    ct += uint32(esop.optionsCalculator().cliffPeriod());
    esop.mockTime(ct);
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    EmpTester emp2 = new EmpTester();
    emp2._target(esop);
    rc = uint(esop.offerOptionsToEmployee(emp2, ct, ct + 2 weeks, 0, false));
    assertEq(rc, 0);
    ct += 2 weeks + 1;
    esop.mockTime(ct);
    rc = emp2.employeeSignsToESOP();
    assertEq(rc, 2, "on deadline + 1");
    // and should be removed
    assertEq(esop.remainingPoolOptions() + maxopts, esop.totalPoolOptions(), "emp2 removed");
  }

  function testOfferDeadlineTooSoon() {
    uint32 ct = esop.currentTime();
    uint rc = uint(esop.offerOptionsToEmployeeOnlyExtra(emp1, ct, ct + esop.MINIMUM_MANUAL_SIGN_PERIOD() - 1, 100000));
    assertEq(rc, 2);
    rc = uint(esop.offerOptionsToEmployee(emp1, ct, ct + esop.MINIMUM_MANUAL_SIGN_PERIOD() - 1, 100000, false));
    assertEq(rc, 2);
  }

  function testConversionOfferDeadlineToSoon() {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 10000, false);
    emp1.employeeSignsToESOP();
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 2);
    esop.mockTime(ct);
    converter = new DummyOptionsConverter(address(esop), ct + esop.MINIMUM_MANUAL_SIGN_PERIOD() - 1 days);
    uint rc = uint(esop.offerOptionsConversion(converter));
    assertEq(rc, 2, "converter");
  }

  function testIncreaseExtraOptions() {
    uint32 ct = esop.currentTime();
    uint rc = uint(esop.offerOptionsToEmployeeOnlyExtra(emp1, ct, ct + 2 weeks, 100000));
    assertEq(rc, 0);
    emp1.employeeSignsToESOP();
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 2);
    esop.mockTime(ct);
    rc = uint(esop.increaseEmployeeExtraOptions(emp1, 20000));
    assertEq(rc, 0);
    uint options = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    assertEq(esop.totalExtraOptions(), 120000, "total extra pool");
    assertEq(options, divRound(120000,2), "vested");
  }

  function testIncreaseEmployeeExtraOptionsNotSigned() {
    // check if extra options can be added when employee not yet signed
    uint32 ct = esop.currentTime();
    uint rc = uint(esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 50000, false));
    assertEq(rc, 0);
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    rc = uint(esop.increaseEmployeeExtraOptions(emp1, 20000));
    assertEq(rc, 0);
    rc = uint(emp1.employeeSignsToESOP());
    assertEq(rc, 0);
    rc = uint(esop.increaseEmployeeExtraOptions(emp1, 30000));
    assertEq(rc, 0);
    ct += uint32(esop.optionsCalculator().vestingPeriod() / 2);
    esop.mockTime(ct);
    uint options = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    assertEq(esop.totalExtraOptions(), 100000, "total extra pool");
    assertEq(options, divRound(100000 + maxopts,2), "vested");
  }

  function testFadeoutMoreThanCliff() {
    // make ESOP with huge residual amount
    esop = makeESOPWithParams(7000);
    emp1._target(esop); // re-target employee proxy!
    // terminate at cliff + 1s
    uint32 ct = esop.currentTime();
    uint rc = uint(esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false));
    assertEq(rc, 0);
    emp1.employeeSignsToESOP();
    uint maxopts = esop.totalPoolOptions() - esop.remainingPoolOptions();
    ct += uint32(esop.optionsCalculator().cliffPeriod() + 1);
    esop.mockTime(ct);
    uint optionsAtCliff = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    if (optionsAtCliff >= divRound(esop.optionsCalculator().residualAmountPromille() * maxopts, esop.optionsCalculator().FP_SCALE())) {
      //@warn this test requires options at cliff < residual amount
      return;
    }
    // terminate employee
    rc = uint(esop.terminateEmployee(emp1, ct, 0));
    assertEq(rc, 0);
    // move by cliff, still should be options at cliff
    ct += uint32(esop.optionsCalculator().cliffPeriod());
    uint finalOpts = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    assertEq(finalOpts, optionsAtCliff, "opts cliff == fade");
    //@info maxopts `uint maxopts` at cliff `uint finalOpts`
  }

  function testFadeoutDuringCliff() {
    uint32 ct = esop.currentTime();
    uint rc = uint(esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false));
    assertEq(rc, 0);
    emp1.employeeSignsToESOP();
    ct += uint32(esop.optionsCalculator().cliffPeriod() / 2);
    esop.mockTime(ct);
    // terminate employee
    rc = uint(esop.terminateEmployee(emp1, ct, 0));
    assertEq(rc, 0);
    // move by cliff, still should be options at cliff
    ct += uint32(esop.optionsCalculator().cliffPeriod());
    uint options = esop.calcEffectiveOptionsForEmployee(address(emp1), ct);
    assertEq(options, 0, "opts fade == 0");
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

  function testThrowOnSecondSetParameters() {
    // options calculator should throw on second call to set parameters
    OptionsCalculator calc = new OptionsCalculator(this);
    calc.setParameters(1 years, 4 years, uint32(calc.FP_SCALE()), uint32(calc.FP_SCALE()), uint32(calc.FP_SCALE()), 1);
    calc.setParameters(1 years, 4 years, uint32(calc.FP_SCALE()), uint32(calc.FP_SCALE()), uint32(calc.FP_SCALE()), 1);
  }

  function testOptionsCalculatorHasSetParameters() {
    OptionsCalculator calc = new OptionsCalculator(this);
    assertEq(calc.hasParameters(), false);
    calc.setParameters(1 years, 4 years, uint32(calc.FP_SCALE()), uint32(calc.FP_SCALE()), uint32(calc.FP_SCALE()), 1);
    assertEq(calc.hasParameters(), true);
  }
}
