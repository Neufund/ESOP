require('babel-register');

const ESOP = artifacts.require("ESOP");
const CALCULATOR = artifacts.require("OptionsCalculator");
const years = 365 * 24 * 60 * 60;

module.exports = function (deployer, network, accounts) {
    // do not deploy options converters on mainnet
    if (network === 'test') {
        deployer.then(async function () {
            let esop = await ESOP.deployed();
            let companyAddress = await esop.companyAddress();
            // open esop
            // function openESOP(uint32 pcliffPeriod, uint32 pvestingPeriod, uint32 pMaxFadeoutPromille, uint32 pbonusOptionsPromille,
            //    uint32 pNewEmployeePoolPromille, uint32 ptotalPoolOptions, bytes pESOPLegalWrapperIPFSHash)
            var ipfsHash = new Buffer("QmRsjnNkEpnDdmYB7wMR7FSy1eGZ12pDuhST3iNLJTzAXF", 'ascii');
            deployer.logger.log('initializing options converter');
            let optcalc = await CALCULATOR.deployed();
            await optcalc.setParameters(1 * years, 4 * years, 8000, 2000, 1000, 500, {from: companyAddress});
            deployer.logger.log('opening esop');
            let tx = await esop.openESOP(1000000, web3.toBigNumber('0x' + ipfsHash.toString('hex')), {from: companyAddress});
            if (tx.logs.some(e => e.event === 'ReturnCode')) {
                // error code returned
                deployer.logger.log(`openESOP returned rc: ${tx.logs[0].args['rc']}`);
                throw `openESOP returned rc: ${tx.logs[0].args['rc']}`;
            }
            deployer.logger.log('esop opened');
        } );
    }
};
