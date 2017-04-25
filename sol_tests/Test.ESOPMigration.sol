pragma solidity ^0.4.8;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.DummyOptionConverter.sol";
import "./Test.Types.sol";

contract NewESOP is ESOPMigration, ESOPTypes, Reporter {
  ESOP oldESOP;
  Employee migratedEmp;

  uint public migratedPoolOptions;
  uint public migratedExtraOptions;

  function getMigratedEmp() public constant returns(uint[9]) {
    return serializeEmployee(migratedEmp);
  }

  // implement abstract functions
  function getOldESOP() public constant returns (address) {
    return oldESOP;
  }

  function migrate(address employee, uint poolOptions, uint extraOptions)
    public
    onlyOldESOP
  {
    // employee in old ESOP is still available
    Employee memory emp = deserializeEmployee(oldESOP.employees().getSerializedEmployee(employee));
    // move emp to storage for later insepection
    migratedEmp = emp;
    // do something with options etc.
    migratedPoolOptions = poolOptions;
    migratedExtraOptions = extraOptions;
  }

  function NewESOP(ESOP pOldESOP) {
    oldESOP = pOldESOP;
  }
}

contract TestESOPMigration is Test, ESOPMaker, Reporter, ESOPTypes, Math
{
    EmpTester emp1;
    ESOP esop;

  function setUp() {
    emp1 = new EmpTester();
    esop = makeNFESOP();
    emp1._target(esop);
  }

  function testEmployeeMigration() {
    NewESOP newesop = new NewESOP(esop);
    EmpTester emp2 = new EmpTester();
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 1290, false);
    uint emp1issued = esop.totalPoolOptions() - esop.remainingPoolOptions();
    esop.offerOptionsToEmployee(emp2, ct, ct + 2 weeks, 7788, false);
    uint emp2issued = esop.totalPoolOptions() - esop.remainingPoolOptions() - emp1issued;
    uint remainingPool = esop.remainingPoolOptions();
    uint totPool = esop.totalPoolOptions();
    emp2._target(esop);
    emp1.employeeSignsToESOP();
    // migration should fail for not signed employee
    uint rc = uint(esop.allowEmployeeMigration(emp2, newesop));
    assertEq(rc, 1, "not signed migration");
    emp2.employeeSignsToESOP();
    uint32 vestp = uint32(esop.optionsCalculator().vestingPeriod());
    esop.mockTime(ct + vestp / 4);
    // migrate to new ESOP at quarter of the vesting
    rc = uint(esop.allowEmployeeMigration(emp2, newesop));
    assertEq(rc, 0, "allow migration");
    rc = uint(emp2.employeeMigratesToNewESOP(newesop));
    assertEq(rc, 0, "migration");
    // employee is no more in old ESOP
    assertEq(esop.employees().hasEmployee(emp2), false, "removed from old");
    // check pool sizes - remaining pool options cannot change!
    assertEq(esop.remainingPoolOptions(), remainingPool, "remaining pool opts");
    // extra options: keeps emp1 + emp2 transferred out
    assertEq(esop.totalExtraOptions(), 1290 + 0);
    // total pool options: old total - emp2 transferred out
    assertEq(esop.totalPoolOptions(), totPool - emp2issued, "total pool opts");
    // check migrated values - quarter of vesting
    assertEq(newesop.migratedPoolOptions(), divRound(emp2issued, 4), "migratedPoolOptions");
    assertEq(newesop.migratedExtraOptions(), divRound(7788, 4), "migratedExtraOptions");
    Employee memory emp = deserializeEmployee(newesop.getMigratedEmp());
    assertEq(emp.poolOptions + emp.extraOptions, emp2issued + 7788, "migrated emp issued");
    // terminate emp1 at quarter vesting
    rc = uint8(esop.terminateEmployee(emp1, ct + vestp / 4, 0));
    assertEq(uint(rc), 0);
    // produce fadeout
    esop.mockTime(ct + vestp / 2);
    // migration should return fadeout
    esop.allowEmployeeMigration(emp1, newesop);
    emp1.employeeMigratesToNewESOP(newesop);
    // check pools
    uint poolfade = esop.optionsCalculator().applyFadeoutToOptions(ct + vestp / 2, ct, ct + vestp / 4, emp1issued, divRound(emp1issued,4));
    uint extrafade = esop.optionsCalculator().applyFadeoutToOptions(ct + vestp / 2, ct, ct + vestp / 4, 1290, divRound(1290,4));
    // remaining pool changed by fadeout and options returned on termination of emp1: remaining - vested - (vested - poolfade) = remaining - 2*vested + poolfade
    assertEq(esop.remainingPoolOptions(), remainingPool + emp1issued - poolfade, "remaining pool opts2");
    // we transferred out all extra options (there is no pool, just total)
    assertEq(esop.totalExtraOptions(), 0, "extra opts2");
    // total pool opts: old total - migrated emp2 (all opts) - migrated emp1 == poolfade (remainder retrurned)
    assertEq(esop.totalPoolOptions(), totPool - emp2issued - poolfade, "total pool opts2");
    // migrated values
    assertEq(newesop.migratedPoolOptions(), poolfade, "migratedPoolOptions2");
    assertEq(newesop.migratedExtraOptions(), extrafade, "migratedExtraOptions2");
  }

  function testThrowMigrationNotAllowed() {
    NewESOP newesop = new NewESOP(esop);
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 1290, false);
    emp1.employeeSignsToESOP();
    emp1.employeeMigratesToNewESOP(newesop);
  }

  function testThrowMigrationDiffers() {
    NewESOP newesop = new NewESOP(esop);
    uint32 ct = esop.currentTime();
    esop.offerOptionsToEmployee(emp1, ct, ct + 2 weeks, 1290, false);
    emp1.employeeSignsToESOP();
    esop.allowEmployeeMigration(emp1, newesop);
    emp1.employeeMigratesToNewESOP(ESOPMigration(esop));
  }

}
