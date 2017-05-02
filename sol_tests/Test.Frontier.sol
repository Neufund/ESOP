pragma solidity ^0.4.8;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.DummyOptionConverter.sol";
import "./Test.Types.sol";

contract TestFrontier is Test, ESOPMaker, Reporter, ESOPTypes, Math
{
    EmpTester emp1;
    ESOP esop;
    DummyOptionsConverter converter;

  function setUp() {
    emp1 = new EmpTester();
    esop = makeNFESOP();
    emp1._target(esop);
  }


}
