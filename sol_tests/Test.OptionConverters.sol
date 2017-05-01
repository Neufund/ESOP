pragma solidity ^0.4.8;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.DummyOptionConverter.sol";
import "./Test.Types.sol";

contract EmpReentry is Reporter {
  address _t;
  function _target( address target ) {
    _t = target;
  }

  function() payable {
    // malicious function that will withdraw again
    if (msg.gas < 21000) return; // do not even try to proceed with low gas limit
    //@info gas `uint msg.gas` balance  `uint this.balance`
    //@info _t `address _t` msg.sender `address msg.sender`
    if (this.balance < 3 ether) {
      bool rv = msg.sender.call(bytes4(keccak256("withdraw()")));
      //@info rv `bool rv`
    }
  }

  function employeeExerciseOptions(bool agreeToAccelConditions) returns (uint8){
      return uint8(ESOP(_t).employeeExerciseOptions(agreeToAccelConditions));
  }

  function employeeSignsToESOP() returns (uint8){
      return uint8(ESOP(_t).employeeSignsToESOP());
  }

  function malicious_withdraw() returns (uint) {
    bool rv = _t.call(bytes4(keccak256("withdraw()")));
  }
}


contract TestOptionConverters is Test, ESOPMaker, Reporter, ESOPTypes, Math {
    EmpTester emp1;
    ESOP esop;

  function setUp() {
    emp1 = new EmpTester();
    //emp2 = new Tester();
    esop = makeNFESOP();
    emp1._target(esop);
  }

  function procERC20OptionsConverter(ERC20OptionsConverter converter, uint32 ct)
    returns (EmpTester, EmpTester, EmpTester)
  {
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 100, false);
    EmpTester emp2 = new EmpTester();
    esop.offerOptionsToEmployee(emp2, ct, ct + 2 weeks, 400, false);
    EmpTester emp3 = new EmpTester();
    esop.offerOptionsToEmployee(emp3, ct, ct + 2 weeks, 800, false);
    uint poolOptions = esop.totalPoolOptions() - esop.remainingPoolOptions();
    uint extraOptions = esop.totalExtraOptions();
    emp1._target(esop);
    emp2._target(esop);
    emp3._target(esop);
    uint rc = uint(emp1.employeeSignsToESOP());
    assertEq(rc, 0, "emp signs");
    emp2.employeeSignsToESOP();
    emp3.employeeSignsToESOP();
    // convert after 3 years to erc20 token (tokenization scenario)
    ct += 3 years;
    esop.mockTime(ct);
    rc = uint(esop.offerOptionsConversion(converter));
    assertEq(rc, 0, "converter");
    uint32 cdead = converter.getExercisePeriodDeadline();
    //convert all users
    emp1.employeeExerciseOptions(true);
    emp2.employeeExerciseOptions(true);
    emp3.employeeExerciseOptions(true);
    // all options converted + exit bonus
    if (absDiff(converter.totalSupply() - extraOptions,
      poolOptions + divRound(poolOptions*esop.optionsCalculator().bonusOptionsPromille(), esop.optionsCalculator().FP_SCALE())) > 1) {
      assertEq(converter.totalSupply() - extraOptions,
        poolOptions + divRound(poolOptions*esop.optionsCalculator().bonusOptionsPromille(), esop.optionsCalculator().FP_SCALE()));
    }

    return (emp1, emp2, emp3);
  }

  function testERC20OptionsConverterTransferBlocked() {
    uint32 deadlineDelta = 3 years + 4 weeks;
    uint32 ct = esop.currentTime();
    ERC20OptionsConverter converter = new ERC20OptionsConverter(esop, ct + deadlineDelta, ct + 2*deadlineDelta);
    var (emp1, emp2, emp3) = procERC20OptionsConverter(converter, ct);
    // transfer function should be blocked
    uint emp1b = converter.balanceOf(emp1);
    uint emp2b = converter.balanceOf(emp2);
    if (emp1b == 0 || emp2b == 0)
      fail();
    emp1._target(converter);
    uint g = 0;
    assembly { g:=gas }
    //@info gas left `uint g`
    bool rv = emp1.forward(bytes4(keccak256("transfer(address,uint256)")), address(emp2), emp1b);
    assertEq(rv, false);
    // if failed, minimum gas is left
    assembly { g:=gas }
    //@info gas left `uint g`
    //@info throw rv `bool rv`
  }

  function testERC20OptionsConverter() {
    uint32 deadlineDelta = 3 years + 4 weeks;
    uint32 ct = esop.currentTime();
    ERC20OptionsConverter converter = new ERC20OptionsConverter(esop, ct + deadlineDelta, ct + 2*deadlineDelta);
    var (emp1, emp2, emp3) = procERC20OptionsConverter(converter, ct);
    // transfer function should be blocked
    uint emp1b = converter.balanceOf(emp1);
    uint emp2b = converter.balanceOf(emp2);
    if (emp1b == 0 || emp2b == 0)
      fail();
    emp1._target(converter);
    // move to a moment when options are released
    ct += 2*deadlineDelta;
    converter.mockTime(ct);
    ERC20OptionsConverter(emp1).transfer(emp2, emp1b);
    assertEq(converter.balanceOf(emp1), 0);
    assertEq(converter.balanceOf(emp2), emp1b + emp2b);
  }

  function testProceedsOptionsConverter() {
    uint32 deadlineDelta = 3 years + 4 weeks;
    uint32 ct = esop.currentTime();
    ProceedsOptionsConverter converter = new ProceedsOptionsConverter(esop, ct + deadlineDelta, ct + 2*deadlineDelta);
    var (emp1, emp2, emp3) = procERC20OptionsConverter(converter, ct);
    ct += 2*deadlineDelta;
    converter.mockTime(ct);
    uint emp1b = converter.balanceOf(emp1);
    uint emp2b = converter.balanceOf(emp2);
    uint totsupp = converter.totalSupply();
    //@info emp1b `uint emp1b` emp2b `uint emp2b` totsupp `uint totsupp`
    // 0 withdrawn before payout
    emp1._target(converter);
    uint cb = emp1.withdraw();
    assertEq(cb, 0, "empty withdrawal");
    // make few payouts
    converter.makePayout.value(2 ether)();
    converter.makePayout.value(5 ether)();
    cb = converter.balance;
    //@info balance `uint cb`
    assertEq(cb, 7 ether, "make payout");
    // withdraw emp1 1
    cb = emp1.withdraw();
    //@info e1 payout `uint cb`
    assertEq(emp1.balance, cb, "e1 rv == balance");
    uint expb = divRound(7 ether * emp1b, totsupp);
    if (absDiff(cb, expb) > 1)
      assertEq(cb, expb, "e1 withdraw amount");
    converter.makePayout.value(1 ether)();
    // emp2 should get share from 3 payouts
    emp2._target(converter);
    cb = emp2.withdraw();
    expb = divRound(8 ether * emp2b, totsupp);
    if (absDiff(cb, expb) > 1)
      assertEq(cb, expb, "e2 withdraw amount");
    // emp1 should get share from last payout
    cb = emp1.withdraw();
    expb = divRound(1 ether * emp1b, totsupp);
    if (absDiff(cb, expb) > 1)
      assertEq(cb, expb, "e1 withdraw 3 payout");
    // emp should get 0
    cb = emp1.withdraw();
    assertEq(cb, 0, "e1 withdraw 0");
    cb = emp2.withdraw();
    assertEq(cb, 0, "e2 withdraw 0");
    // total ether invariant
    assertEq(8 ether, converter.balance + emp1.balance + emp2.balance, "total ether");
    emp3._target(converter);
    cb = emp3.withdraw();
    //@info emp3 payout `uint cb`
    assertEq(converter.balance, 0, "all paid out");
  }

  function testThrowProceedsWithdrawnTransferFrom() {
    uint32 deadlineDelta = 3 years + 4 weeks;
    uint32 ct = esop.currentTime();
    ProceedsOptionsConverter converter = new ProceedsOptionsConverter(esop, ct + deadlineDelta, ct + 2*deadlineDelta);
    var (emp1, emp2, emp3) = procERC20OptionsConverter(converter, ct);
    ct += deadlineDelta;
    converter.mockTime(ct);
    uint emp1b = converter.balanceOf(emp1);
    converter.makePayout.value(5 ether)();
    emp1._target(converter);
    uint cb = emp1.withdraw();
    // should throw
    ERC20OptionsConverter(emp1).transfer(emp2, emp1b);
  }

  function testThrowProceedsWithdrawnTransferTo() {
    uint32 deadlineDelta = 3 years + 4 weeks;
    uint32 ct = esop.currentTime();
    ProceedsOptionsConverter converter = new ProceedsOptionsConverter(esop, ct + deadlineDelta, ct + 2*deadlineDelta);
    var (emp1, emp2, emp3) = procERC20OptionsConverter(converter, ct);
    ct += deadlineDelta;
    converter.mockTime(ct);
    uint emp1b = converter.balanceOf(emp1);
    uint emp2b = converter.balanceOf(emp2);
    converter.makePayout.value(5 ether)();
    emp1._target(converter);
    emp2._target(converter);
    uint cb = emp1.withdraw();
    // should throw
    ERC20OptionsConverter(emp2).transfer(emp1, emp2b);
  }

  function testProceedsWithdrawalReentry() {
    EmpReentry emp1 = new EmpReentry();
    EmpTester emp0 = new EmpTester();
    EmpTester empx = new EmpTester();
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp0, ct, ct + 2 weeks, 100, false);
    esop.offerOptionsToEmployee(empx, ct, ct + 2 weeks, 400, false);
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 2876, false);
    emp1._target(esop);
    emp1.employeeSignsToESOP();
    emp0._target(esop);
    empx._target(esop);
    emp0.employeeSignsToESOP();
    empx.employeeSignsToESOP();
    esop.mockTime(ct + 3 years);
    uint32 deadlineDelta = 3 years + 4 weeks;
    ProceedsOptionsConverter converter = new ProceedsOptionsConverter(esop, ct + deadlineDelta, ct + 2*deadlineDelta);
    uint rc = uint(esop.offerOptionsConversion(converter));
    assertEq(rc, 0, "converter");
    emp1.employeeExerciseOptions(true);
    emp0.employeeExerciseOptions(true);
    empx.employeeExerciseOptions(true);
    converter.mockTime(ct + 2*deadlineDelta);
    // now emp1 tries to withdraw multiple times
    uint emp1b = converter.balanceOf(emp1);
    converter.makePayout.value(5 ether)();
    emp1._target(converter);
    emp1.malicious_withdraw();
    //uint cb = emp1.withdraw();
    uint expbalance = divRound((5 ether * emp1b), converter.totalSupply());
    assertEq(emp1.balance, expbalance, "no re-entry");
    uint stolen = emp1.balance - expbalance;
    //@warn `uint stolen` wei stolen
    //assertEq(cb, emp1.balance, "faithful rv");
  }

  function testProceedsOptionsConverterOptionsDenied() {
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 1289, false);
    uint emp1issued = esop.totalPoolOptions() - esop.remainingPoolOptions();
    emp1.employeeSignsToESOP();
    uint32 vestp = uint32(esop.optionsCalculator().vestingPeriod());
    esop.mockTime(ct + vestp / 2);
    uint32 deadlineDelta = vestp / 2 + 4 weeks;
    ProceedsOptionsConverter converter = new ProceedsOptionsConverter(esop, ct + deadlineDelta, ct + deadlineDelta + 1 weeks);
    // options offered in half of the vesting
    uint rc = uint(esop.offerOptionsConversion(converter));
    assertEq(rc, 0, "converter");
    // agrees to accel vesting
    rc = uint(emp1.employeeDenyExerciseOptions());
    assertEq(rc, 0, "deny exercise");
    // total supply should be 0
    assertEq(converter.totalSupply(), 0);
    // burned to 0 address 0 options
    assertEq(converter.balanceOf(address(0)), 0);
  }
}
