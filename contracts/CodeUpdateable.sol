pragma solidity ^0.4.8;
import "./Types.sol";


contract CodeUpdateable is Ownable {
    // allows to stop operations and migrate data to different contract
    enum CodeUpdateState { CurrentCode, OngoingUpdate /*, CodeUpdated*/}
    CodeUpdateState public codeUpdateState;

    modifier isCurrentCode() {
      if (codeUpdateState != CodeUpdateState.CurrentCode)
        throw;
      _;
    }

    modifier inCodeUpdate() {
      if (codeUpdateState != CodeUpdateState.OngoingUpdate)
        throw;
      _;
    }

    function beginCodeUpdate() public onlyOwner isCurrentCode {
      codeUpdateState = CodeUpdateState.OngoingUpdate;
    }

    function cancelCodeUpdate() public onlyOwner inCodeUpdate {
      codeUpdateState = CodeUpdateState.CurrentCode;
    }

    function completeCodeUpdate() public onlyOwner inCodeUpdate {
      selfdestruct(owner);
    }
}
