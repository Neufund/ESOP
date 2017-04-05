pragma solidity ^0.4.0;

contract Ownable {
  // replace with proper zeppelin smart contract
  address public owner;

  function Ownable() {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    if (msg.sender != owner)
      throw;
    _;
  }

  function transferOwnership(address newOwner) onlyOwner {
    // @remco: Why not transfer + accept to prevent invalid transfers?
    if (newOwner != address(0)) owner = newOwner;
  }
}


contract Math {
  // todo: should be a library

  // These functions can be labeled `internal`.
  // No need to have them in the ABI.

  function divRound(uint v, uint d) public constant returns(uint) {
    // round up if % is half or more
    // Why not `(v + (d/2)) / d` ?
    return v/d + (v % d >= (d%2 == 1 ? d/2+1 : d/2) ? 1: 0);
  }

  function absDiff(uint v1, uint v2) public constant returns(uint) {
    // !! This depends on both uint-underflow and out-of-range casting to int.
    // Both of these are not part of the Solidity language standard
    // and can break without warning in future version.
    // Why not `a > b ? a - b : b - a`?
    return v1 >= v2 ? v1 - v2 : uint(-(int(v1 - v2)));
  }

  function safeMul(uint a, uint b) public constant returns (uint) {
    // This overflows first, and then checks. But checking for overflow in
    // multiply is hard.
    uint c = a * b;
    if (a == 0 || c / a == b)
      return c;
    else
      throw;
  }
}


// TestRPC has functions for mocking the time, that would make this
// contract uneccessary?
contract TimeSource is Ownable {
  uint32 mockNow; // private

  function currentTime() public constant returns (uint32) {
    // we do not support dates much into future (Sun, 07 Feb 2106 06:28:15 GMT)
    if (block.timestamp > 0xFFFFFFFF)
      throw;
    // alow to return debug time on test nets etc.
    if (block.number > 3316029)
      return uint32(block.timestamp);
    else
      return mockNow > 0 ? mockNow : uint32(block.timestamp);
  }

  function mockTime(uint32 t) public onlyOwner {
    mockNow = t;
  }
}

contract Upgradeable is Ownable {
    // allows to stop operations and upgrade
    enum MigrationState { Operational, OngoingMigration, Migrated}
    MigrationState public migrationState;

    modifier notInMigration() {
      if (migrationState != MigrationState.Operational)
        throw;
      _;
    }

    modifier inMigration() {
      if (migrationState != MigrationState.OngoingMigration)
        throw;
      _;
    }
    modifier migrated() {
      if (migrationState != MigrationState.Migrated)
        throw;
      _;
    }

    function kill() onlyOwner migrated {
      selfdestruct(owner);
    }

    // Maybe store/inform users where to migrate to?
    function beginMigration() public onlyOwner notInMigration {
        migrationState = MigrationState.OngoingMigration;
    }

    function cancelMigration() public onlyOwner inMigration {
      migrationState = MigrationState.Operational;
    }

    function completeMigration() public onlyOwner inMigration {
      migrationState = MigrationState.Migrated;
    }

    // Events ?
}
