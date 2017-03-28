var RoT = artifacts.require("./RoT.sol");
var ESOP = artifacts.require("./ESOP.sol");

module.exports = function (deployer, network, accounts) {

    deployer.deploy(ESOP, accounts[0], RoT.address).then(
        function() {

            /*console.log(RoT);
             console.log('-------------------------------------------');
             console.log(RoT.deployed);
             console.log('-------------------------------------------');
             console.log(RoT.deployed());
             console.log('-------------------------------------------');*/
            RoT.deployed().then(function (instance) {
                instance.setESOP(ESOP.address);
            });
        }
    );
    /*deployer.then(function () {
        deployer.deploy(RoT);
        return RoT.address;
    }).then(function (i) {
        rot_i = i;
        //console.log('RoT deployed at: ' + String(rot_i.address));
        return ESOP.new();
    }).then(function (i) {
        console.log('ESOP deployed at: ' + String(i.address));
        rot_i.setESOP(i.address);
        return i;
    });*/
};
