pragma solidity ^0.4.0;

import "./ESOP.sol";

contract EmpTester {
  address _t;
  function _target( address target ) {
    _t = target;
  }
  function() {
    if(!_t.call(msg.data)) throw;
  }

  function employeeConvertsOptions() returns (uint8){
      return uint8(ESOP(_t).employeeConvertsOptions());
  }

  function employeeSignsToESOP() returns (uint8){
      return uint8(ESOP(_t).employeeSignsToESOP());
  }

  function calcEffectiveOptionsForEmployee(address e, uint32 calcAtTime) returns (uint) {
    return ESOP(_t).calcEffectiveOptionsForEmployee(e, calcAtTime);
  }
}

//contract ESOPTest is ESOP
