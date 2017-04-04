require('babel-register');

const RoT = artifacts.require("RoT");
const ESOP = artifacts.require("ESOP");

module.exports = function (deployer, network) {
    deployer.then( async function() {
        await deployer.deploy(RoT);
        let rot = await RoT.deployed();
        var ceoAddr;
        if (network == 'live')
            ceoAddr = ''; // provide CEO address that will manage contract on live network
        else {
            ceoAddr = await rot.owner(); // on other networks deploying account is the CEO
        }
        deployer.logger.log(`Assuming account ${ceoAddr} as a CEO`);
        await deployer.deploy(ESOP, ceoAddr, RoT.address);
        deployer.logger.log(`Setting ESOP address in RoT to ${ESOP.address}`);
        await rot.setESOP(ESOP.address, ceoAddr);
    });
};
