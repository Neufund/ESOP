require('babel-register');
const MIGRATIONS = artifacts.require("Migrations");

module.exports = function (deployer, network, accounts) {
    deployer.then(async function () {
        /*deployer.logger.log(MIGRATIONS.address);
        let migrations = await MIGRATIONS.deployed();
        await migrations.selfdestruct();
        deployer.logger.log('migrations destroyed');*/
    } );
};
