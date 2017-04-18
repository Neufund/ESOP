require('babel-register');

const ESOP = artifacts.require("ESOP");
const CALCULATOR = artifacts.require("OptionsCalculator");
const EMPLIST = artifacts.require("EmployeesList");
const years = 365 * 24 * 60 * 60;

module.exports = function (deployer, network, accounts) {
    // do not deploy options converters on mainnet
    if (network != 'live') {
        deployer.then(async function () {
            let esop = await ESOP.deployed();
            // open esop
            // function openESOP(uint32 pcliffPeriod, uint32 pvestingPeriod, uint32 pMaxFadeoutPromille, uint32 pbonusOptionsPromille,
            //    uint32 pNewEmployeePoolPromille, uint32 ptotalPoolOptions, bytes pESOPLegalWrapperIPFSHash)
            var ipfsHash = new Buffer("QmRsjnNkEpnDdmYB7wMR7FSy1eGZ12pDuhST3iNLJTzAXF", 'ascii');
            await deployer.deploy(CALCULATOR, 1 * years, 4 * years, 8000, 2000, 1000, 500);
            let optcals = await CALCULATOR.deployed();
            await deployer.deploy(EMPLIST);
            let emplist = await EMPLIST.deployed();
            await emplist.transferOwnership(ESOP.address);
            deployer.logger.log('opening esop');
            let tx = await esop.openESOP(CALCULATOR.address, EMPLIST.address, 1000000, web3.toBigNumber('0x' + ipfsHash.toString('hex')));
            if (tx.logs.some(e => e.event == 'ReturnCode')) {
                // error code returned
                deployer.logger.log(`openESOP returned rc: ${tx.logs[0].args['rc']}`);
                throw `openESOP returned rc: ${tx.logs[0].args['rc']}`;
            }
            deployer.logger.log('esop opened');
            //let company = await esop.companyAddress();

        } );
    }
};
