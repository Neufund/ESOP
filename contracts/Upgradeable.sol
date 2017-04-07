pragma solidity ^0.4.0;
import "./Types.sol";

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
