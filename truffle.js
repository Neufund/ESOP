require('babel-register')

module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      gas: 4000000, // close to current mainnet limit
      network_id: "*" // Match any network id
    },
    paritydev: {
      host: "localhost",
      port: 8444,
      network_id: "17",
      // from: "0xFAFfd72A5fc6375eac399cce6141210723bd8889" // my nano S
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
