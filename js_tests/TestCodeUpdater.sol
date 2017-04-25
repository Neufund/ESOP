pragma solidity ^0.4.8;
import "../contracts/ESOP.sol";

// used to group code update transactions and provide atomicity
contract TestCodeUpdater is Ownable, Destructable, ESOPTypes {
  EmployeesList private oldList;
  EmployeesList private newList;
  event RV(int rc);

  function migrateEmployeesList(uint fromidx, uint maxcount)
    external
    onlyOwner
    returns (int count)
  {
    // copy maxount employees from old to new list
    Employee memory emp;
    uint max_i = fromidx + maxcount > oldList.size() ? oldList.size() : fromidx + maxcount;
    for(uint i=fromidx; i< max_i; i++) {
      address ea = oldList.addresses(i);
      if (ea != 0) { // address(0) is deleted employee
        emp = deserializeEmployee(oldList.getSerializedEmployee(ea));
        // here you can change data and schema, we just copy
        newList.setEmployee(ea, emp.issueDate, emp.timeToSign, emp.terminatedAt, emp.fadeoutStarts, emp.poolOptions,
          emp.extraOptions, emp.suspendedAt, emp.state);
        count++;
      }
    }
    RV(count);
    return count;
  }

  function transferEmployeesListOwnership(address newOwner)
    external
    onlyOwner
  {
    newList.transferOwnership(newOwner);
  }

  function TestCodeUpdater(EmployeesList ol, EmployeesList nl) Ownable() {
    oldList = ol;
    newList = nl;
  }
}
