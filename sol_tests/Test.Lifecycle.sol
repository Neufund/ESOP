pragma solidity ^0.4.0;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.DummyOptionConverter.sol";
import "./Test.Types.sol";

contract TestLifecycle is Test, ESOPMaker, Reporter, ESOPTypes
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

  function procLifecycleOptions(uint32 ct, uint totOptions)
  {
    uint options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, 0, "on creation");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 2 weeks);
    assertEq(options, 0, "on sign expiration");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 3 weeks);
    assertEq(options, 0, "after sign expiration");
    emp1.employeeSignsToESOP();
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, 0, "on creation signed");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct+uint32(esop.cliffDuration())-1);
    assertEq(options, 0, "cliff - 1s");
    uint cliffOpts = esop.divRound(totOptions * esop.cliffDuration(), esop.vestingDuration());
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct+uint32(esop.cliffDuration()));
    assertEq(options, cliffOpts, "on cliff");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct+uint32(esop.cliffDuration())+1);
    assertEq(options, cliffOpts, "on cliff + 1s");
    ct += uint32(esop.vestingDuration());
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct-1);
    assertEq(options, totOptions, "vesting end - 1s");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, totOptions, "vesting end");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct+1);
    assertEq(options, totOptions, "vesting end + 1s");
    // terminate in half vesting
    ct -= uint32(esop.vestingDuration()/2);
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, totOptions/2, "half vesting");
    esop.terminateEmployee(emp1, ct, 0);
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, totOptions/2, "half vesting term");
    // half fadeout
    ct += uint32(esop.vestingDuration()/4);
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    uint minFade = esop.divRound(totOptions*(esop.fpScale() - esop.maxFadeoutPromille()), esop.fpScale());
    // if minFade > vested options then vested options is the min value after fadeout (basically - no fadeout in this case)
    if (minFade >= totOptions/2)
      minFade = totOptions/2;
    uint halfFade = minFade + (totOptions/2 - minFade)/2;
    assertEq(options, halfFade, "half fadeout");
    // full fadout
    ct += uint32(esop.vestingDuration()/4);
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct - 1);
    assertEq(options, minFade, "full fadeout - 1s");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, minFade, "full fadeout");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1);
    assertEq(options, minFade, "full fadeout + 1s");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1 years);
    assertEq(options, minFade, "full fadeout + 1y");
    // convert at half fadeout
    ct -= uint32(esop.vestingDuration()/4);
    IOptionsConverter converter = new DummyOptionsConverter(address(esop), ct + 2 years);
    esop.mockTime(ct);
    uint8 rc = uint8(esop.convertESOPOptions(ct, converter));
    assertEq(uint(rc), 0, "convertESOPOptions");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, halfFade, "half fade conversion");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1 years);
    assertEq(options, halfFade, "half fade conversion + 1y");
    // employee conversion
    esop.mockTime(ct + 1 weeks);
    emp1.employeeConvertsOptions();
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1 years);
    assertEq(options, 0, "employee converted options");
  }

  function procLifecycleJustBonus(uint32 ct, uint totOptions, uint extraOptions)
  {
    emp1.employeeSignsToESOP();
    ct += uint32(esop.vestingDuration()) + 1 years;
    uint options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, totOptions, "1y after vesting");
    IOptionsConverter converter = new DummyOptionsConverter(address(esop), ct + 2 years);
    esop.mockTime(ct);
    uint8 rc = uint8(esop.convertESOPOptions(ct, converter));
    assertEq(uint(rc), 0, "convertESOPOptions");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct);
    assertEq(options, totOptions + esop.divRound((totOptions-extraOptions)*esop.exitBonusPromille(), esop.fpScale()), "exit bonus");
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1 years);
    assertEq(options, totOptions + esop.divRound((totOptions-extraOptions)*esop.exitBonusPromille(), esop.fpScale()), "exit bonus + 1y");
    // employee conversion
    esop.mockTime(ct + 1 weeks);
    emp1.employeeConvertsOptions();
    options = emp1.calcEffectiveOptionsForEmployee(emp1, ct + 1 years);
    assertEq(options, 0, "employee converted options");
  }

  function testLifecycleOptionsTermFade()
  {
    // test amount of options at various employee lifecycle event
    uint32 ct = esop.currentTime();
    esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 0, false);
    uint poolOptions = esop.totalOptions() - esop.remainingOptions();
    emp1._target(esop);
    procLifecycleOptions(ct, poolOptions);
  }

  function testLifecycleExtraOptionsTermFade()
  {
    // test amount of options at various employee lifecycle event
    uint32 ct = esop.currentTime();
    esop.addEmployeeWithExtraOptions(emp1, ct, ct + 2 weeks, 8000);
    emp1._target(esop);
    procLifecycleOptions(ct, 8000);
  }

  function testLifecycleCombinedOptionsTermFade()
  {
    // test amount of options at various employee lifecycle event
    uint32 ct = esop.currentTime();
    esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 8000, false);
    uint poolOptions = esop.totalOptions() - esop.remainingOptions();
    emp1._target(esop);
    procLifecycleOptions(ct, poolOptions + 8000);
  }

  function testLifecycleOptionsJustBonus()
  {
    uint32 ct = esop.currentTime();
    esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 0, false);
    uint poolOptions = esop.totalOptions() - esop.remainingOptions();
    emp1._target(esop);
    procLifecycleJustBonus(ct, poolOptions, 0);
  }

  function testLifecycleExtraOptionsJustBonus()
  {
    uint32 ct = esop.currentTime();
    esop.addEmployeeWithExtraOptions(emp1, ct, ct + 2 weeks, 8000);
    emp1._target(esop);
    procLifecycleJustBonus(ct, 8000, 8000);
  }

  function testLifecycleCombinedOptionsJustBonus()
  {
    uint32 ct = esop.currentTime();
    esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 8000, false);
    uint poolOptions = esop.totalOptions() - esop.remainingOptions();
    emp1._target(esop);
    procLifecycleJustBonus(ct, poolOptions + 8000, 8000);
  }
}
