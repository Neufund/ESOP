require('babel-register');

const ESOP = artifacts.require("ESOP");
const years = 365 * 24 * 60 * 60;
const currdate = (new Date()) / 1;
const weeks = 7 * 24 * 60 * 60;

module.exports = function (deployer, network, accounts) {
    // do not deploy options converters on mainnet
    if (network != 'live') {
        deployer.then(async function () {
            let esop = await ESOP.deployed();
            // open esop
            // function openESOP(uint32 pCliffDuration, uint32 pVestingDuration, uint32 pMaxFadeoutPromille, uint32 pExitBonusPromille,
            //    uint32 pNewEmployeePoolPromille, uint32 pTotalOptions, bytes pPoolEstablishmentDocIPFSHash)
            var ipfsHash = new Buffer("QmRsjnNkEpnDdmYB7wMR7FSy1eGZ12pDuhST3iNLJTzAXF", 'ascii');
            deployer.logger.log('opening esop');
            let tx = await esop.openESOP(1 * years, 4 * years, 8000, 2000, 1000, 1000000, web3.toBigNumber('0x' + ipfsHash.toString('hex')));
            if (tx.logs.some(e => e.event == 'ReturnCode')) {
                // error code returned
                deployer.logger.log(`openESOP returned rc: ${tx.logs[0].args['rc']}`);
                throw `openESOP returned rc: ${tx.logs[0].args['rc']}`;
            }
            deployer.logger.log('esop opened');
            let ceo = await esop.addressOfCEO();
            let startdate = currdate;
            accounts.filter(a => a !== ceo).map(async function(e) {
                // function addNewEmployeeToESOP(address e, uint32 vestingStarts, uint32 timeToSign, uint32 extraOptions, bool poolCleanup)
                let tx = await esop.addNewEmployeeToESOP(e, startdate - 1 * weeks, startdate + 4 * weeks, 0, false);
                if (tx.logs.some(e => e.event === 'NewEmployee')) {
                    deployer.logger.log(`employee ${e} added with ${tx.logs[0].args['options']} options`);
                } else {
                    deployer.logger.log(`addNewEmployeeToESOP returned rc: ${tx.logs[0].args['rc']}`);
                    throw `addNewEmployeeToESOP returned rc: ${tx.logs[0].args['rc']}`;
                }
            });
        } );
    }
};