pragma solidity ^0.4.8;

import "./ESOP.sol";
import "./RoT.sol";
import "./ERC20OptionsConverter.sol";
import "./ProceedsOptionsConverter.sol";
import "./ESOPMigration.sol";

contract EmpTester {
  address _t;
  function _target( address target ) {
    _t = target;
  }
  function() payable {
    if (msg.data.length > 0) // do not call default function on target
      if(!_t.call(msg.data)) throw;
  }

  function forward(bytes4 signature, address a, uint256 v) returns (bool) {
    return _t.call(signature, a, v);
  }

  function employeeExerciseOptions(bool agreeToAccelConditions) returns (uint8){
      return uint8(ESOP(_t).employeeExerciseOptions(agreeToAccelConditions));
  }

  function employeeDenyExerciseOptions() returns (uint8){
      return uint8(ESOP(_t).employeeDenyExerciseOptions());
  }

  function employeeMigratesToNewESOP(ESOPMigration m) returns (uint8){
      return uint8(ESOP(_t).employeeMigratesToNewESOP(m));
  }

  function employeeSignsToESOP() returns (uint8){
      return uint8(ESOP(_t).employeeSignsToESOP());
  }

  function calcEffectiveOptionsForEmployee(address e, uint32 calcAtTime) returns (uint) {
    return ESOP(_t).calcEffectiveOptionsForEmployee(e, calcAtTime);
  }

  function withdraw() returns (uint) {
    return ProceedsOptionsConverter(_t).withdraw();
  }

  /*uint32 pcliffPeriod, uint32 pvestingPeriod, uint32 pMaxFadeoutPromille, uint32 pbonusOptionsPromille,
    uint32 pNewEmployeePoolPromille
    pcliffPeriod, pvestingPeriod, pMaxFadeoutPromille, pbonusOptionsPromille, pNewEmployeePoolPromille*/
  function openESOP(uint32 ptotalPoolOptions, bytes pESOPLegalWrapperIPFSHash) returns (uint8) {
      return uint8(ESOP(_t).openESOP(ptotalPoolOptions, pESOPLegalWrapperIPFSHash));
    }
}

contract ESOPMaker {
  RoT public root;

  function makeNFESOP() public returns (ESOP) {
    return makeESOPWithParams(5000);
  }

  function makeESOPWithParams(uint32 residualAmount) public returns (ESOP) {
    root = new RoT();
    OptionsCalculator optcalc = new OptionsCalculator(address(this));
    EmployeesList emplist = new EmployeesList();
    ESOP e = new ESOP(address(this), address(root), optcalc, emplist);
    root.setESOP(e, address(this));
    //bytes32 ESOPLegalWrapperIPFSHash = sha256("hereby pool #1 is established");
    bytes memory ESOPLegalWrapperIPFSHash = "qmv8ndh7ageh9b24zngaextmuhj7aiuw3scc8hkczvjkww";
    // a few interesting parameter combinations
    // e.openESOP(1 years, 4 years, 2000, 2000, 1000, 1000000, ESOPLegalWrapperIPFSHash) - neufund
    // e.openESOP(0 years, 4 years, 2000, 2000, 1000, 1000000, ESOPLegalWrapperIPFSHash) - no cliff
    // e.openESOP(0 years, 0 years, 2000, 2000, 1000, 1000000, ESOPLegalWrapperIPFSHash) - no vesting
    // e.openESOP(1 years, 4 years, 0, 2000, 1000, 1000000, ESOPLegalWrapperIPFSHash) - full fadeout
    // e.openESOP(1 years, 4 years, 10000, 2000, 1000, 1000000, ESOPLegalWrapperIPFSHash) - no fadeout
    // e.openESOP(1 years, 4 years, 2000, 0, 1000, 1000000, ESOPLegalWrapperIPFSHash) - no bonus
    // e.openESOP(1 years, 4 years, 2000, 0, 0, 0, ESOPLegalWrapperIPFSHash) - no pool, just extra
    emplist.transferOwnership(e);
    // company calls this
    optcalc.setParameters(1 years, 4 years, residualAmount, 2000, 1000, 360);
    uint rc = uint(e.openESOP(833400, ESOPLegalWrapperIPFSHash));
    if (rc != 0)
      throw;
    return e;
  }
}

//contract ESOPTest is ESOP
