// hardhat import should be the first import in the file
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import * as hardhat from "hardhat";
import { Command } from "commander";
import { Wallet } from "ethers";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import * as fs from "fs";
import * as path from "path";
import { Deployer } from "../src.ts/deploy";
import { GAS_MULTIPLIER, web3Provider } from "./utils";
import { ADDRESS_ONE, encodeNTVAssetId, isCurrentNetworkLocal } from "../src.ts/utils";
import { getTokens } from "../src.ts/deploy-token";

const ETH_TOKEN_ADDRESS = ADDRESS_ONE;

const provider = web3Provider();
const testConfigPath = path.join(process.env.ZKSYNC_HOME as string, "etc/test_config/constant");
const ethTestConfig = JSON.parse(fs.readFileSync(`${testConfigPath}/eth.json`, { encoding: "utf-8" }));

const getTokenAddress = async (name: string) => {
  const tokens = getTokens();
  const token = tokens.find((token: { symbol: string }) => token.symbol == name);
  if (!token) {
    throw new Error(`Token ${name} not found`);
  }
  if (!token.address) {
    throw new Error(`Token ${name} has no address`);
  }
  return token.address;
};

// If base token is eth, we are ok, otherwise we need to check if token is deployed
const checkTokenAddress = async (address: string) => {
  if (address == ETH_TOKEN_ADDRESS) {
    return;
  } else if ((await provider.getCode(address)) == "0x") {
    throw new Error(`Token ${address} is not deployed`);
  }
};

// If:
// * base token name is provided, we find its address
// * base token address is provided, we use it
// * neither is provided, we fallback to eth
const chooseBaseTokenAddress = async (name?: string, address?: string) => {
  if (name) {
    return getTokenAddress(name);
  } else if (address) {
    return address;
  } else {
    return ETH_TOKEN_ADDRESS;
  }
};

async function main() {
  const program = new Command();

  program.version("0.1.0").name("register-zk-chain").description("register zk-chains");

  program
    .option("--private-key <private-key>")
    .option("--gas-price <gas-price>")
    .option("--nonce <nonce>")
    .option("--governor-address <governor-address>")
    .option("--only-verifier")
    .option("--validium-mode")
    .option("--base-token-name <base-token-name>")
    .option("--base-token-address <base-token-address>")
    .option("--use-governance")
    .option("--token-multiplier-setter-address <token-multiplier-setter-address>")
    .option("--allow-evm-emulation")
    .action(async (cmd) => {
      const deployWallet = cmd.privateKey
        ? new Wallet(cmd.privateKey, provider)
        : Wallet.fromMnemonic(
            process.env.MNEMONIC ? process.env.MNEMONIC : ethTestConfig.mnemonic,
            "m/44'/60'/0'/0/1"
          ).connect(provider);
      console.log(`Using deployer wallet: ${deployWallet.address}`);

      const ownerAddress = cmd.governorAddress || deployWallet.address;
      console.log(`Using governor address: ${ownerAddress}`);

      const gasPrice = cmd.gasPrice
        ? parseUnits(cmd.gasPrice, "gwei")
        : (await provider.getGasPrice()).mul(GAS_MULTIPLIER);
      console.log(`Using gas price: ${formatUnits(gasPrice, "gwei")} gwei`);

      const nonce = cmd.nonce ? parseInt(cmd.nonce) : await deployWallet.getTransactionCount();
      console.log(`Using nonce: ${nonce}`);

      const deployer = new Deployer({
        deployWallet,
        ownerAddress,
        verbose: true,
        l1ChainId: process.env.CONTRACTS_L1_CHAIN_ID || "31337",
      });

      const baseTokenAddress = await chooseBaseTokenAddress(cmd.baseTokenName, cmd.baseTokenAddress);
      await checkTokenAddress(baseTokenAddress);
      console.log(`Using base token address: ${baseTokenAddress}`);
      console.log(deployer.addresses.Bridgehub.BridgehubProxy);
      const baseTokenAssetId = encodeNTVAssetId(deployer.l1ChainId, baseTokenAddress);
      if (!(await deployer.bridgehubContract(deployWallet).assetIdIsRegistered(baseTokenAssetId))) {
        await deployer.registerTokenBridgehub(baseTokenAddress, cmd.useGovernance);
      }
      if (baseTokenAddress != ETH_TOKEN_ADDRESS) {
        await deployer.registerTokenInNativeTokenVault(baseTokenAddress);
      }
      await deployer.registerZKChain(
        baseTokenAssetId,
        cmd.validiumMode,
        null,
        gasPrice,
        true,
        null,
        null,
        cmd.useGovernance,
        isCurrentNetworkLocal() || cmd.localLegacyBridgeTesting
      );

      const tokenMultiplierSetterAddress = cmd.tokenMultiplierSetterAddress || "";

      if (tokenMultiplierSetterAddress != "") {
        console.log(`Using token multiplier setter address: ${tokenMultiplierSetterAddress}`);
        await deployer.setTokenMultiplierSetterAddress(tokenMultiplierSetterAddress);
      }

      if (cmd.allowEvmEmulation) {
        console.log("Allowing EVM emulation");
        await deployer.enableEvmEmulation();
      }

      await deployer.transferAdminFromDeployerToChainAdmin();
    });

  await program.parseAsync(process.argv);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err);
    process.exit(1);
  });
