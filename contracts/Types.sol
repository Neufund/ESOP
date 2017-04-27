pragma solidity ^0.4.8;


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
    if (newOwner != address(0))
      owner = newOwner;
  }
}


contract Destructable is Ownable {
  function selfdestruct() external onlyOwner {
    // free ethereum network state when done
    selfdestruct(owner);
  }
}


contract Math {
  // scale of the emulated fixed point operations
  uint constant public FP_SCALE = 10000;

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

  function safeAdd(uint a, uint b) internal constant returns (uint) {
    uint c = a + b;
    if (!(c>=a && c>=b))
      throw;
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
    if (block.number > 3316029)
      throw;
    mockNow = t;
  }
}
