pragma solidity ^0.4.0;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.DummyOptionConverter.sol";
import "./Test.Types.sol";

contract TestFrontier is Test, ESOPMaker, Reporter, ESOPTypes
{
    EmpTester emp1;
    ESOP esop;

  function setUp() {
    emp1 = new EmpTester();
    //emp2 = new Tester();
    //esop = new ESOP();
    //emp1._target(esop);
  }

}
