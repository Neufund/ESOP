pragma solidity ^0.4.0;
import "./Types.sol";

contract ESOPTypes {
  // enums are numbered starting from 0. NotSet is used to check for non existing mapping
  enum EmployeeState { NotSet, WaitingForSignature, Employed, Terminated, GoodWillTerminated, OptionsExercised }
  // please note that 32 bit unsigned int is used to represent UNIX time which is enough to represent dates until Sun, 07 Feb 2106 06:28:15 GMT
  // storage access is optimized so struct layout is important
  struct Employee {
      // when vesting starts
      uint32 issueDate;
      // wait for employee signature until that time
      uint32 timeToSign;
      // date when employee was terminated, 0 for not terminated
      uint32 terminatedAt;
      // when fade out starts, 0 for not set, initally == terminatedAt
      // used only when calculating options returned to pool
      uint32 fadeoutStarts;
      // poolOptions employee gets (exit bonus not included)
      uint32 poolOptions;
      // extra options employee gets (neufund will not this option)
      uint32 extraOptions;
      // size of the group of the employees that were added together
      // uint8 groupSize;
      // what is employee current status, takes 8 bit in storage
      EmployeeState state;
      // index in iterable mapping
      uint16 idx;
      // reserve until full 256 bit word
      //uint56 reserved;
  }
}
