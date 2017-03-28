pragma solidity ^0.4.0;
import "./Types.sol";

contract RoT is Ownable
{
    address public ESOPAddress;

    // change esop contract
    function setESOP(address ESOP) public onlyOwner {
      ESOPAddress = ESOP;
    }
}
