pragma solidity ^0.4.0;
import "../contracts/ESOP.sol";


contract UpdatedESOP is ESOP {
  // test updated ESOP with new set of rules
  function migrateState(ESOP old, OptionsCalculator newCalculator, EmployeesList newEmployees, bytes newLegalWrapperHash)
    external
    onlyOwner
  {
    // copy state from old ESOP
    totalPoolOptions = old.totalPoolOptions();
    companyAddress = old.companyAddress();
    rootOfTrust = old.rootOfTrust();
    remainingPoolOptions = old.remainingPoolOptions();
    esopState = old.esopState();
    totalExtraOptions = old.totalExtraOptions();
    conversionOfferedAt = old.conversionOfferedAt();
    exerciseOptionsDeadline = old.exerciseOptionsDeadline();
    optionsConverter = old.optionsConverter();
    // set updated instances
    optionsCalculator = newCalculator;
    employees = newEmployees;
    ESOPLegalWrapperIPFSHash = newLegalWrapperHash;
  }
  function UpdatedESOP(address company, address pRootOfTrust) ESOP(company, pRootOfTrust) {
    // freeze logic
    beginCodeUpdate();
  }
}
