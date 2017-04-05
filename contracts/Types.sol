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
    if (newOwner != address(0)) owner = newOwner;
  }
}


contract Math {
  // todo: should be a library
  function divRound(uint v, uint d) internal constant returns(uint) {
    // round up if % is half or more
    return (v + (d/2)) / d;
  }

  function absDiff(uint v1, uint v2) public constant returns(uint) {
    return v1 > v2 ? v1 - v2 : v2 - v1;
  }

  function safeMul(uint a, uint b) public constant returns (uint) {
    uint c = a * b;
    if (a == 0 || c / a == b)
      return c;
    else
      throw;
  }

  function safeAdd(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    if (!(c>=a && c>=b)) throw;
    return c;
  }
}


contract TimeSource {
  uint32 private mockNow;

  function currentTime() public constant returns (uint32) {
    // we do not support dates much into future (Sun, 07 Feb 2106 06:28:15 GMT)
    if (block.timestamp > 0xFFFFFFFF)
      throw;
    return mockNow > 0 ? mockNow : uint32(block.timestamp);
  }

  function mockTime(uint32 t) public {
    // no mocking on mainnet
    if (block.number > 3316029) throw;
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
