pragma solidity ^0.4.8;

import 'dapple/test.sol';
import 'dapple/reporter.sol';
import "./Test.Types.sol";

contract TestFrontier is Test, Reporter, Math
{

  function setUp() {
  }

  function testAbsDiff() {
    assertEq(absDiff(5, 3), absDiff(3,5));
    assertEq(absDiff(5, 3), 2);
    // two's complement will be used
    assertEq(absDiff(uint(-5), uint(-3)), 2);
  }

  function testDivRound() {
    assertEq(divRound(1871, 11), 170, "round up");
    assertEq(divRound(12871, 2), 6436, "round up from 0.5");
    assertEq(divRound(10,2), 5, "no round");
    assertEq(divRound(81542, 23), 3545, "round down");
  }

}
