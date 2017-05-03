require('babel-register');

const RoT = artifacts.require("RoT");
const ESOP = artifacts.require("ESOP");
const CALCULATOR = artifacts.require("OptionsCalculator");
const EMPLIST = artifacts.require("EmployeesList");

module.exports = function (deployer, network, accounts) {
    deployer.then(async function () {
        await deployer.deploy(RoT);
        let rot = await RoT.deployed();
        var companyAddress;
        if (network === 'live') {
            // provide company address that will manage contract on live network
            companyAddress = '';
        }
        else if (network === 'ropsten') {
          // company role public address on ropsten
          companyAddress = '0x1078291bbcc539f51559f14bc57d1575d3801df8';
        }
        else {
            // 0 is default account, make company to use account 1
            companyAddress = accounts[1];
        }
        deployer.logger.log(`Assuming account ${companyAddress} as a company`);
        await deployer.deploy(CALCULATOR, companyAddress);
        let optcalc = await CALCULATOR.deployed();
        // company owns options calculator
        await deployer.deploy(EMPLIST);
        let emplist = await EMPLIST.deployed();
        await deployer.deploy(ESOP, companyAddress, RoT.address, CALCULATOR.address, EMPLIST.address);
        // esop contract owns employee's list
        await emplist.transferOwnership(ESOP.address);
        deployer.logger.log(`Setting ESOP address in RoT to ${ESOP.address}`);
        await rot.setESOP(ESOP.address, companyAddress);
    });
};
