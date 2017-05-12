require('babel-register');

module.exports = {
    networks: {
        development: {
            host: "localhost",
            port: 8545,
            network_id: "*" // Match any network id
        },
        test: {
            host: "localhost",
            port: 8545,
            gas: 4800000, // close to current ropsten limit
            network_id: "192837992"
        },
        test_deployment: {
            host: "localhost",
            port: 8546,
            gas: 4100000, // close to current mainnet limit
            network_id: "192837991"
        },
        paritydev: {
            host: "localhost",
            port: 8444,
            network_id: "17",
        },
        ropsten: {
            host: "localhost", // local parity ropsten node with nano attached
            port: 8545,
            network_id: "3",
            // from: '0xDba5a21D0B5DEAD8D63d5A4edf881005751211C2' // public key of admin role
        },
        kovan: {
            host: "localhost", // local parity ropsten node with nano attached
            port: 8545,
            network_id: "42",
            from: '0xE459a8c206B2E91d998CFBB187D0efc4FC7e92D3' // public key of admin role
        },
        "live": {
            network_id: 1 // Ethereum public network
            // optional config values
            // host - defaults to "localhost"
            // port - defaults to 8545
            // gas
            // gasPrice
            // from - default address to use for any transaction Truffle makes during migrations
        }
    }
};
