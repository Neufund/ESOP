require('babel-register');

const ESOP = artifacts.require("ESOP");
const ERC20OptionsConverter = artifacts.require("ERC20OptionsConverter");
const ProceedsOptionsConverter = artifacts.require("ProceedsOptionsConverter");

module.exports = function (deployer, network) {
    // do not deploy options converters on mainnet
    if (network === 'test') {
        deployer.then(async function () {
            const esop = await ESOP.deployed();
            const year_ahead = Math.floor(new Date() / 1000) + 365 * 24 * 60 * 60;
            const month_duration = 30 * 24 * 60 * 60;
            // options conversion activated in 1 year and availale for 30 days
            await deployer.deploy(ERC20OptionsConverter, esop.address, year_ahead, year_ahead + month_duration);
            await deployer.deploy(ProceedsOptionsConverter, esop.address, year_ahead, year_ahead + month_duration);
            deployer.logger.log(`conversion deadline is ${year_ahead}`);
        });
    }
};
