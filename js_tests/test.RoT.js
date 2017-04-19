require('babel-register');

const RoT = artifacts.require("RoT");
const ESOP = artifacts.require("ESOP");

contract('RoT', function () {
  it('rot should selfdestruct', async () => {
      let rot = await RoT.deployed();
      let companyAddress = await rot.owner();
      // now selfdestruct
      let rotcode = web3.eth.getCode(rot.address);
      // console.log(rotcode);
      await rot.killOnUnsupportedFork({from: companyAddress});
      let nocode = web3.eth.getCode(rot.address);
      // console.log(nocode);
      assert.equal('0x0', nocode, 'bytecode should be 0x0');

  });
});
