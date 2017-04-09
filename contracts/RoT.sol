pragma solidity ^0.4.0;
import "./Types.sol";

contract RoT is Ownable {
    address public ESOPAddress;
    event ESOPAndCEOSet(address ESOPAddress, address ceoAddress);

    function setESOP(address ESOP, address company) public onlyOwner {
      // owner sets ESOP and company only once then passes ownership to company
      // initially owner is a developer/admin
      ESOPAddress = ESOP;
      transferOwnership(company);
      ESOPAndCEOSet(ESOP, company);
    }

    function killOnUnsupportedFork() public onlyOwner {
      // this method may only be called by company on unsupported forks
      delete ESOPAddress;
      selfdestruct(owner);
    }
}
