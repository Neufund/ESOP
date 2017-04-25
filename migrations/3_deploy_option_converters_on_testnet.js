require('babel-register');

const ESOP = artifacts.require("ESOP");
const ERC20OptionsConverter = artifacts.require("ERC20OptionsConverter");
const ProceedsOptionsConverter = artifacts.require("ProceedsOptionsConverter");

module.exports = function (deployer, network) {
    // do not deploy options converters on mainnet
    if (network === 'test') {
        deployer.then(async function () {
            let year_ahead = Math.floor(new Date() / 1000) + 365 * 24 * 60 * 60;
            await deployer.deploy(ERC20OptionsConverter, ESOP.address, year_ahead);
            await deployer.deploy(ProceedsOptionsConverter, ESOP.address, year_ahead);
            deployer.logger.log(`conversion deadline is ${year_ahead}`);
        });
    }
};
