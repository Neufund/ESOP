pragma solidity ^0.4.8;
import "./Types.sol";


contract RoT is Ownable {
    address public ESOPAddress;
    event ESOPAndCompanySet(address ESOPAddress, address companyAddress);

    function setESOP(address ESOP, address company) public onlyOwner {
      // owner sets ESOP and company only once then passes ownership to company
      // initially owner is a developer/admin
      ESOPAddress = ESOP;
      transferOwnership(company);
      ESOPAndCompanySet(ESOP, company);
    }

    function killOnUnsupportedFork() public onlyOwner {
      // this method may only be called by company on unsupported forks
      delete ESOPAddress;
      selfdestruct(owner);
    }
}
