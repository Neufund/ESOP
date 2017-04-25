pragma solidity ^0.4.8;
import "../contracts/ESOP.sol";


contract UpdatedESOP is ESOP {
  // test updated ESOP with new set of rules
  function migrateState(ESOP old, bytes newLegalWrapperHash)
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

    ESOPLegalWrapperIPFSHash = newLegalWrapperHash;
  }
  function UpdatedESOP(address company, address pRootOfTrust, OptionsCalculator newCalculator, EmployeesList newEmployees)
    ESOP(company, pRootOfTrust, newCalculator, newEmployees) {
    // freeze logic
    beginCodeUpdate();
  }
}

contract UpdatedOptionsCalculator is OptionsCalculator {
  function migrateState(OptionsCalculator oldcal)
    external
    onlyOwner
  {
    cliffPeriod = oldcal.cliffPeriod();
    vestingPeriod = oldcal.vestingPeriod();
    maxFadeoutPromille = oldcal.maxFadeoutPromille();
    bonusOptionsPromille = oldcal.bonusOptionsPromille();
    newEmployeePoolPromille = oldcal.newEmployeePoolPromille();
    optionsPerShare = oldcal.optionsPerShare();
  }

  function UpdatedOptionsCalculator(address companyAddress)
    OptionsCalculator(companyAddress)
  {}
}
