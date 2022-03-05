import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-gas-reporter";
import "@openzeppelin/hardhat-upgrades";

const mnemonic = "0x9ff006c8d75a6e31317be003dd82d5f88d64ab7b2b5e1ec7f7f5ae227f2b0e5d"

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    defaultNetwork: "harmony_testnet",
    networks: {
        localhost: {
            url: "http://127.0.0.1:8545"
        },
        hardhat: {},
        bscmainnet: {
            url: "https://bsc-dataseed.binance.org/",
            chainId: 56,
            gasPrice: 20000000000,
            accounts: [`${mnemonic}`]
        },
        rinkeby: {
            url: 'https://speedy-nodes-nyc.moralis.io/b6a2f439eeb57f2c3c4334a6/eth/rinkeby',
            // url: 'https://rinkeby.infura.io/v3/f8bdc9ea610d4e3d9f7d07c4d76bb08e',
            gas: 8500000,
            chainId: 4,
            accounts: [`${mnemonic}`]
        },
        harmony_testnet: {
            url: `https://api.s0.b.hmny.io`,
            accounts: [`${mnemonic}`]
        },
        harmony_mainnet: {
            url: `https://api.harmony.one`,
            accounts: [`${mnemonic}`]
        }
    },
    etherscan: {
        apiKey: "981PMBPPGP7G535A89BDW7XWC6XFIX4EDN"
    },
    solidity: {
        version: "0.8.2",
        settings: {
            optimizer: {
                enabled: true
            }
        }
    },
    paths: {
        sources: "./contracts",
        tests: "./test",
        cache: "./cache",
        artifacts: "./artifacts"
    },
    mocha: {
        timeout: 20000
    },
    typechain: {
        outDir: "typechain",
        target: "ethers-v5",
    },
    gasReporter: {
        currency: "USD",
        gasPrice: 25,
        // enabled: process.env.REPORT_GAS ? true : false,
    },
};
