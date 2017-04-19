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
        if (network === 'live')
            companyAddress = ''; // provide company address that will manage contract on live network
        else {
            // 0 is default account, make company to use account 2
            companyAddress = accounts[1]; // on other networks deploying account is the company
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
