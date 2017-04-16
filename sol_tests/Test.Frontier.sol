pragma solidity ^0.4.0;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.DummyOptionConverter.sol";
import "./Test.Types.sol";

contract TestFrontier is Test, ESOPMaker, Reporter, ESOPTypes, Math
{
    EmpTester emp1;
    ESOP esop;

  function setUp() {
    emp1 = new EmpTester();
    //emp2 = new Tester();
    esop = makeNFESOP();
    emp1._target(esop);
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

  function testEmployeeDeniesToExerciseOptions() {}

    function testERC20OptionsConverterOptionsDenied() {
      // check how it handles burn!

    }

  function testConversionStopsSuspended() {}

    // test extractVestedOptionsComponents

    // test migrations: pool, process etc

}
