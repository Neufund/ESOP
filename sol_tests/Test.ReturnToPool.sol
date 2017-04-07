pragma solidity ^0.4.0;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.DummyOptionConverter.sol";
import "./Test.Types.sol";

contract TestReturnToPool is Test, ESOPMaker, Reporter, ESOPTypes, Math
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

  function prepExpectedOptionsAmount(uint count, ESOP E) returns (uint[])
  {
    // calculate option amount for 'count' employees
    uint[] memory options = new uint[](count);
    uint remPool = E.totalOptions();
    for(uint i=0; i<count; i++)
    {
      uint o = (remPool * E.newEmployeePoolPromille()) / E.FP_SCALE();
      options[i] = o;
      remPool -= o;
    }
    return options;
  }

  function massAddEmployees(uint count, ESOP E) returns (address[])
  {
    uint32 ct = E.currentTime();
    address[] memory employees = new address[](count);
    for(uint i=0; i<count; i++) {
      emp1 = new EmpTester();
      employees[i] = emp1;
      E.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 0, false);
      emp1._target(E);
    }
    return employees;
  }

  function massAddEmployeesExtra(uint count, ESOP E) returns (address[], uint[])
  {
    uint32 ct = E.currentTime();
    address[] memory employees = new address[](count);
    uint[] memory emp_options = new uint[](count);
    uint initExtra = 8000;
    for(uint i=0; i<count; i++) {
      emp1 = new EmpTester();
      employees[i] = emp1;
      emp_options[i] = initExtra;
      E.addEmployeeWithExtraOptions(emp1, ct, ct + 2 weeks, uint32(initExtra));
      emp1._target(E);
      initExtra += 8000;
    }
    return (employees, emp_options);
  }

  function checkOptionsInEmployeeList(EmployeesList employees, uint[] options)
  {
    Employee memory emp;
    uint j=0;
    uint size = employees.size();
    assertEq(size, options.length, "optcheck sizes must be equal");
    for(uint i=0; i< size; i++) {
      address ea = employees.addresses(i);
      if (ea != 0) { // address(0) is deleted employee
        var sere = employees.getSerializedEmployee(ea);
        assembly { emp := sere }
        //@info `uint emp.options` `uint options[j]`
        if (esop.absDiff(emp.options, options[j]) > 1)
          assertEq(uint(emp.options), options[j], "optcheck options");
        j++;
      }
      else {
        //@info emp at `uint i` removed
      }
    }
    //@info found `uint j` employees
  }

  function testFadeoutExtraToPool()
  {
    uint32 ct = esop.currentTime();
    uint extraOptions = 10000;
    esop.addEmployeeWithExtraOptions(emp1, ct, ct + 2 weeks, uint32(extraOptions));
    uint rc = uint(emp1.employeeSignsToESOP());
    assertEq(rc, 0);
    // employee leaves on vesting end day
    uint32 term_t = ct+uint32(esop.vestingDuration());
    esop.mockTime(term_t);
    rc = uint(esop.terminateEmployee(emp1, term_t, 0));
    assertEq(rc,0);
    uint32 delta_t = uint32(esop.vestingDuration());
    uint fade = divRound(esop.maxFadeoutPromille() * extraOptions, esop.FP_SCALE());
    uint tot_fade;
    for(uint i=0; i<10; i++) {
      delta_t = uint32(divRound(delta_t, 2));
      term_t += delta_t;
      fade = divRound(fade, 2);
      tot_fade += fade;
      //@info iter `uint i` fade `uint fade` tot fade `uint tot_fade`
      uint copts = esop.calcEffectiveOptionsForEmployee(emp1, term_t);
      // there are scaling errors, until nice fixed point lib is made I will not fight that
      if (esop.absDiff(copts, extraOptions - tot_fade)>2)
        assertEq(copts, extraOptions - tot_fade, "tot opts - fade");
      // return fadeout
      esop.mockTime(term_t);
      uint ppool = esop.totalExtraOptions();
      esop.returnFadeoutToPool();
      if (esop.absDiff(ppool - esop.totalExtraOptions(), fade) > 2)
        assertEq(ppool - esop.totalExtraOptions(), fade, "pool eqs fade");
      // also check if still the same options are calculated on termination
    }
    // check both extra and normal pool
  }

  function testFadeoutToPool()
  {
    uint32 ct = esop.currentTime();
    esop.addNewEmployeeToESOP(emp1, ct, ct + 2 weeks, 0, false);
    uint poolOptions = esop.totalOptions() - esop.remainingOptions();
    uint rc = uint(emp1.employeeSignsToESOP());
    assertEq(rc, 0);
    // employee leaves on vesting end day
    uint32 term_t = ct+uint32(esop.vestingDuration());
    esop.mockTime(term_t);
    rc = uint(esop.terminateEmployee(emp1, term_t, 0));
    assertEq(rc,0);
    uint32 delta_t = uint32(esop.vestingDuration());
    uint fade = divRound(esop.maxFadeoutPromille() * poolOptions, esop.FP_SCALE());
    uint tot_fade;
    for(uint i=0; i<10; i++) {
      delta_t = uint32(divRound(delta_t, 2));
      term_t += delta_t;
      fade = divRound(fade, 2);
      tot_fade += fade;
      //@info iter `uint i` fade `uint fade` tot fade `uint tot_fade`
      uint copts = esop.calcEffectiveOptionsForEmployee(emp1, term_t);
      // there are scaling errors, until nice fixed point lib is made I will not fight that
      if (esop.absDiff(copts, poolOptions - tot_fade) > 3)
        assertEq(copts, poolOptions - tot_fade, "tot opts - fade");
      // return fadeout
      esop.mockTime(term_t);
      rc = esop.remainingOptions();
      esop.returnFadeoutToPool();
      if (esop.absDiff(esop.remainingOptions() - rc, fade) > 2)
        assertEq(esop.remainingOptions() - rc, fade, "pool eqs fade");
      // also check if still the same options are calculated on termination
    }
    // check both extra and normal pool
  }

  function testTerminateEmployeeToPool()
  {
    ESOP E = makeNFESOP();
    address[] memory employees = massAddEmployees(7, E);
    uint[] memory options = prepExpectedOptionsAmount(7, E);
    // sign and terminate employee no 2
    uint32 ct = E.currentTime();
    uint rc = uint(EmpTester(employees[3]).employeeSignsToESOP());
    assertEq(rc, 0);
    rc = uint(EmpTester(employees[1]).employeeSignsToESOP());
    assertEq(rc, 0);
    uint ppool = E.remainingOptions();
    // terminate exactly half way so half options are returned
    uint32 term_t = ct+uint32(E.vestingDuration()/2);
    E.mockTime(term_t);
    rc = uint(E.terminateEmployee(employees[3], term_t, 0));
    assertEq(rc,0);
    uint vested = divRound(options[3],2);
    //@info vesting should be half of options `uint vested` of `uint options[3]`
    // now modify reference list by distributing vested part
    for(uint i=4; i<7; i++) {
      uint modopt = divRound(vested * E.newEmployeePoolPromille(), E.FP_SCALE());
      vested -= modopt;
      options[i] += modopt;
    }
    checkOptionsInEmployeeList(E.employees(), options);
    // now check remaining pool
    if (absDiff(E.remainingOptions(), ppool + vested) > 1)
      assertEq(E.remainingOptions(), ppool + vested, "all back in pool");
    // now terminate one more
    rc = uint(E.terminateEmployee(employees[1], term_t, 0));
    assertEq(rc,0);
    uint vested2 = divRound(options[1],2);
    for(i=2; i<7; i++) {
        if (i != 3) { //skip already terminated employee
          modopt = divRound(vested2 * E.newEmployeePoolPromille(), E.FP_SCALE());
          vested2 -= modopt;
          options[i] += modopt;
      }
    }
    checkOptionsInEmployeeList(E.employees(), options);
    if (absDiff(E.remainingOptions(), ppool + vested + vested2) > 1)
      assertEq(E.remainingOptions(), ppool + vested + vested2, "all back in pool 2");
  }

  function testSignaturesExpiredToPool() logs_gas
  {
    ESOP E = makeNFESOP();
    address[] memory employees = massAddEmployees(15, E);
    uint[] memory options = prepExpectedOptionsAmount(15, E);
    // check pool before anything expires
    //@info `uint[] options`
    checkOptionsInEmployeeList(E.employees(), options);
    // mark one as employed
    uint rc = uint(EmpTester(employees[5]).employeeSignsToESOP());
    assertEq(rc, 0);
    // now expire signatures
    uint32 ct = E.currentTime();
    E.mockTime(ct+4 weeks);
    rc = uint(EmpTester(employees[7]).employeeSignsToESOP());
    // must return too late
    assertEq(rc, 2);
    checkOptionsInEmployeeList(E.employees(), options);
    rc = uint(EmpTester(employees[3]).employeeSignsToESOP());
    // must return too late
    assertEq(rc, 2);
    checkOptionsInEmployeeList(E.employees(), options);
    rc = uint(EmpTester(employees[14]).employeeSignsToESOP());
    // must return too late
    assertEq(rc, 2);
    checkOptionsInEmployeeList(E.employees(), options);
    // now return everyting in loop
    for(uint i=0; i<15; i++) {
      if(E.employees().hasEmployee(employees[i])) {
        EmpTester(employees[i]).employeeSignsToESOP();
        checkOptionsInEmployeeList(E.employees(), options);
      }
    }
    // all should be back in pool - employeed employee options
    Employee memory emp;
    var sere = E.employees().getSerializedEmployee(employees[5]);
    assembly { emp := sere }
    assertEq(E.totalOptions(), E.remainingOptions() + emp.options, "all back in pool");
  }

  function testRemoveSignaturesExpiredToPool() logs_gas
  {
    ESOP E = makeNFESOP();
    address[] memory employees = massAddEmployees(15, E);
    uint[] memory options = prepExpectedOptionsAmount(15, E);
    // check pool before anything expires
    //@info `uint[] options`
    checkOptionsInEmployeeList(E.employees(), options);
    // now expire signatures
    uint32 ct = E.currentTime();
    E.mockTime(ct+4 weeks);
    E.removeEmployeesWithExpiredSignatures();
    // all should be back in pool
    assertEq(E.totalOptions(), E.remainingOptions(), "all back in pool");
  }

  function testRemoveSignaturesExpiredToPoolOneEmployed() logs_gas
  {
    ESOP E = makeNFESOP();
    address[] memory employees = massAddEmployees(15, E);
    uint[] memory options = prepExpectedOptionsAmount(15, E);
    EmpTester(employees[0]).employeeSignsToESOP();
    // check pool before anything expires
    //@info `uint[] options`
    checkOptionsInEmployeeList(E.employees(), options);

    // now expire signatures
    uint32 ct = E.currentTime();
    E.mockTime(ct+4 weeks);
    E.removeEmployeesWithExpiredSignatures();
    // all should be back in pool
    assertEq(E.totalOptions(), E.remainingOptions() + options[0], "all back in pool");
  }

  function testRemoveSignaturesExpiredToPoolOneEmployedTerminatedExtra() logs_gas
  {
    ESOP E = makeNFESOP();
    var (employees, options) = massAddEmployeesExtra(15, E);
    EmpTester(employees[7]).employeeSignsToESOP();
    EmpTester(employees[3]).employeeSignsToESOP();
    //@info `uint[] options`
    uint sumOptions = 0;
    for(uint i=0; i<options.length; i++)
      sumOptions += options[i];
    assertEq(E.totalExtraOptions(), sumOptions, "fill extra pool");
    // now expire signatures
    uint32 ct = E.currentTime() + uint32(E.vestingDuration()/2);
    E.mockTime(ct);
    // terminate employee 3 at half of a vesting
    E.terminateEmployee(employees[3], ct, 0);
    E.removeEmployeesWithExpiredSignatures();
    // all should be back in pool
    assertEq(E.totalExtraOptions(), options[7] + divRound(options[3],2), "all back in pool");
  }
}
