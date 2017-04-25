pragma solidity ^0.4.8;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.DummyOptionConverter.sol";
import "./Test.Types.sol";

contract TestLifecycle is Test, ESOPMaker, Reporter, ESOPTypes, Math
{
    EmpTester emp1;
    //Tester emp2;
    ESOP esop;
    //DummyOptionsConverter converter;

  function setUp() {
    emp1 = new EmpTester();
    //emp2 = new Tester();
    esop = makeNFESOP();
    emp1._target(esop);
    //converter = new DummyOptionsConverter(address(esop));
  }

  function procLifecycleOptions(uint32 ct, uint totOptions) {
    uint options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, 0, "on creation");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 2 weeks);
    assertEq(options, 0, "on sign expiration");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 3 weeks);
    assertEq(options, 0, "after sign expiration");
    assertEq(uint(emp1.employeeSignsToESOP()), 0, "sign to ESOP");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, 0, "on creation signed");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct+uint32(esop.optionsCalculator().cliffPeriod())-1);
    assertEq(options, 0, "cliff - 1s");
    uint cliffOpts = divRound(totOptions * esop.optionsCalculator().cliffPeriod(), esop.optionsCalculator().vestingPeriod());
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct+uint32(esop.optionsCalculator().cliffPeriod()));
    assertEq(options, cliffOpts, "on cliff");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct+uint32(esop.optionsCalculator().cliffPeriod())+1);
    assertEq(options, cliffOpts, "on cliff + 1s");
    ct += uint32(esop.optionsCalculator().vestingPeriod());
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct-1);
    assertEq(options, totOptions, "vesting end - 1s");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, totOptions, "vesting end");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct+1);
    assertEq(options, totOptions, "vesting end + 1s");
    // terminate in half vesting
    ct -= uint32(esop.optionsCalculator().vestingPeriod()/2);
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(totOptions,2), "half vesting");
    assertEq(uint(esop.terminateEmployee(emp1, ct, 0)), 0, "terminate employee");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, divRound(totOptions,2), "half vesting term");
    // half fadeout
    ct += uint32(esop.optionsCalculator().vestingPeriod()/4);
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    uint minFade = divRound(totOptions*(esop.optionsCalculator().FP_SCALE() - esop.optionsCalculator().maxFadeoutPromille()), esop.optionsCalculator().FP_SCALE());
    // if minFade > vested options then vested options is the min value after fadeout (basically - no fadeout in this case)
    if (minFade >= divRound(totOptions,2))
      minFade = totOptions/2;
    uint halfFade = minFade + divRound((divRound(totOptions,2) - minFade),2);
    assertEq(options, halfFade, "half fadeout");
    // full fadout
    ct += uint32(esop.optionsCalculator().vestingPeriod()/4);
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct - 1);
    assertEq(options, minFade, "full fadeout - 1s");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, minFade, "full fadeout");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1);
    assertEq(options, minFade, "full fadeout + 1s");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1 years);
    assertEq(options, minFade, "full fadeout + 1y");
    // convert at half fadeout
    ct -= uint32(esop.optionsCalculator().vestingPeriod()/4);
    BaseOptionsConverter converter = new DummyOptionsConverter(address(esop), ct + 2 years);
    esop.mockTime(ct);
    uint8 rc = uint8(esop.offerOptionsConversion(converter));
    assertEq(uint(rc), 0, "offerOptionsConversion");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, halfFade, "half fade conversion");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1 years);
    assertEq(options, halfFade, "half fade conversion + 1y");
    // employee conversion
    esop.mockTime(ct + 1 weeks);
    emp1.employeeExerciseOptions(true);
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1 years);
    assertEq(options, 0, "employee converted options");
  }

  function procLifecycleJustBonus(uint32 ct, uint totOptions, uint extraOptions)
  {
    emp1.employeeSignsToESOP();
    ct += uint32(esop.optionsCalculator().vestingPeriod()) + 1 years;
    uint options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, totOptions, "1y after vesting");
    BaseOptionsConverter converter = new DummyOptionsConverter(address(esop), ct + 2 years);
    esop.mockTime(ct);
    uint8 rc = uint8(esop.offerOptionsConversion(converter));
    assertEq(uint(rc), 0, "offerOptionsConversion");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, totOptions + divRound((totOptions-extraOptions)*esop.optionsCalculator().bonusOptionsPromille(), esop.optionsCalculator().FP_SCALE()), "exit bonus");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1 years);
    assertEq(options, totOptions + divRound((totOptions-extraOptions)*esop.optionsCalculator().bonusOptionsPromille(), esop.optionsCalculator().FP_SCALE()), "exit bonus + 1y");
    // employee conversion
    esop.mockTime(ct + 1 weeks);
    emp1.employeeExerciseOptions(true);
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1 years);
    assertEq(options, 0, "employee converted options");
  }

  function testLifecycleOptionsTermFade()
  {
    // test amount of options at various employee lifecycle event
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false);
    uint poolOptions = esop.totalPoolOptions() - esop.remainingPoolOptions();
    emp1._target(esop);
    procLifecycleOptions(ct, poolOptions);
  }

  function testLifecycleExtraOptionsTermFade()
  {
    // test amount of options at various employee lifecycle event
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployeeOnlyExtra(emp1, ct, ct + 2 weeks, 8000);
    emp1._target(esop);
    procLifecycleOptions(ct, 8000);
  }

  function testLifecycleCombinedOptionsTermFade()
  {
    // test amount of options at various employee lifecycle event
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 8000, false);
    uint poolOptions = esop.totalPoolOptions() - esop.remainingPoolOptions();
    emp1._target(esop);
    procLifecycleOptions(ct, poolOptions + 8000);
  }

  function testLifecycleOptionsJustBonus()
  {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 0, false);
    uint poolOptions = esop.totalPoolOptions() - esop.remainingPoolOptions();
    emp1._target(esop);
    procLifecycleJustBonus(ct, poolOptions, 0);
  }

  function testLifecycleExtraOptionsJustBonus()
  {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployeeOnlyExtra(emp1, ct, ct + 2 weeks, 8000);
    emp1._target(esop);
    procLifecycleJustBonus(ct, 8000, 8000);
  }

  function testLifecycleCombinedOptionsJustBonus()
  {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 8000, false);
    uint poolOptions = esop.totalPoolOptions() - esop.remainingPoolOptions();
    emp1._target(esop);
    procLifecycleJustBonus(ct, poolOptions + 8000, 8000);
  }
}
