pragma solidity ^0.4.0;
import "./Types.sol";

contract RoT is Ownable {
    address public ESOPAddress;
    event ESOPAndCEOSet(address ESOPAddress, address ceoAddress);

    function setESOP(address ESOP, address ceo) public onlyOwner {
      // owner sets ESOP and ceo only once then passes ownership to ceo
      // initially owner is a developer/admin
      ESOPAddress = ESOP;
      transferOwnership(ceo);
      ESOPAndCEOSet(ESOP, ceo);
    }

    function killOnUnsupportedFork() public onlyOwner {
      // this method may only be called by CEO on unsupported forks
      delete ESOPAddress;
      selfdestruct(owner);
    }
}
