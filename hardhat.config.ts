import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-ethers"
import "hardhat-deploy"
import "hardhat-deploy-ethers"
import "hardhat-gas-reporter"
import "dotenv/config"
import { HardhatUserConfig } from "hardhat/config"

const MAINNET_RPC = "https://rpc-mainnet.maticvigil.com"
const MUMBAI_RPC = "https://rpc-mumbai.maticvigil.com/"

const config: HardhatUserConfig = {
    etherscan: {
        apiKey: process.env.POLYGONSCAN_API_KEY,
    },
    networks: {
        matic: {
            url: MAINNET_RPC,
            chainId: 137,
            live: true,
            saveDeployments: true,
            accounts: [process.env.PRIVATE_KEY],
        },
        mumbai: {
            url: MUMBAI_RPC,
            chainId: 80001,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [process.env.PRIVATE_KEY],
        },
    },
    gasReporter: {
        enabled: true,
        currency: "USD",
        outputFile: "gas-report.txt",
        noColors: true,
    },
    solidity: {
        version: "0.8.17",
        settings: {
            optimizer: {
                enabled: true,
                runs: 1000000,
            },
        },
    },
}

export default config
