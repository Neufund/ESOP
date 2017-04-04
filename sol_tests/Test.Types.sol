pragma solidity ^0.4.0;

import "./ESOP.sol";
import "./RoT.sol";
import "./ERC20OptionsConverter.sol";
import "./ProceedsOptionsConverter.sol";

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

  function employeeConvertsOptions() returns (uint8){
      return uint8(ESOP(_t).employeeConvertsOptions());
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

  function openESOP(uint32 pCliffDuration, uint32 pVestingDuration, uint32 pMaxFadeoutPromille, uint32 pExitBonusPromille,
    uint32 pNewEmployeePoolPromille, uint32 pTotalOptions, bytes pPoolEstablishmentDocIPFSHash) returns (uint8) {
      return uint8(ESOP(_t).openESOP(pCliffDuration, pVestingDuration, pMaxFadeoutPromille, pExitBonusPromille, pNewEmployeePoolPromille,
        pTotalOptions, pPoolEstablishmentDocIPFSHash));
    }
}

contract ESOPMaker {
  RoT public root;

  function makeNFESOP() public returns (ESOP) {
    root = new RoT();
    ESOP e = new ESOP(address(this), address(root));
    root.setESOP(e, address(this));
    //bytes32 poolEstablishmentDocIPFSHash = sha256("hereby pool #1 is established");
    bytes memory poolEstablishmentDocIPFSHash = "qmv8ndh7ageh9b24zngaextmuhj7aiuw3scc8hkczvjkww";
    // make CEO sign this
    uint rc = uint(e.openESOP(1 years, 4 years, 8000, 2000, 1000, 1000000, poolEstablishmentDocIPFSHash));
    if (rc != 0)
      throw;
    return e;
  }
}

//contract ESOPTest is ESOP
