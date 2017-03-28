var RoT = artifacts.require("./RoT.sol");

module.exports = function (deployer, network, accounts) {
    deployer.deploy(RoT);
};
