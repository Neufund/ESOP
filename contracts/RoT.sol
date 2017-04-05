pragma solidity ^0.4.0;
import "./Types.sol";

contract RoT is Ownable {
    address public ESOPAddress;
    address public addressOfCEO;

    // change esop contract
    function setESOP(address ESOP, address ceo) public onlyOwner {
      addressOfCEO = ceo;
      ESOPAddress = ESOP;
    }

    function killOnUnsupportedFork() public {
      // this method may only be called by CEO on unsupported forks
      if (msg.sender != addressOfCEO) throw;
      delete ESOPAddress;
      delete addressOfCEO;
      selfdestruct(owner);
    }
    
    // Events?
}
