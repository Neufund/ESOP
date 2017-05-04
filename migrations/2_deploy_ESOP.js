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
            companyAddress = '0xa55e5ce2a6f5fbd66ef3d5a5a6407e1b6bedd1c9';
        }
        else if (network == 'paritydev') {
            // local paritu dev company account
            // priv key is c017c5558bed2c8d6ce3b7a488dcbeb470cad1127cbbf024d27322397b2d69ba
            companyAddress = '0x911b1edc92211a549eb1d7080046d631113a148b';
        }
        else if (network === 'kovan') {
            // company role public address on kovan
            companyAddress = '0xFAFfd72A5fc6375eac399cce6141210723bd8889';
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
