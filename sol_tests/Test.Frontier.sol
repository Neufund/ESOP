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

  function testESOPInstantiation() {
    RoT root = new RoT();
    ESOP e = new ESOP(address(this), address(root));
    root.setESOP(e);
    bytes memory poolEstablishmentDocIPFSHash = "qmv8ndh7ageh9b24zngaextmuhj7aiuw3scc8hkczvjkww";
    // make CEO sign this
    uint rc = uint(e.openESOP(1 years, 4 years, 8000, 2000, 1000, 1000000, poolEstablishmentDocIPFSHash));
    assertEq(rc, 0);
  }
}
