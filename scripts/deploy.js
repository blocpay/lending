const { ethers } = require("hardhat");

async function main() {
  function getAddresses(contracts) {
    return {
      BorrowerOperations: contracts.borrowerOperations.address,
      PriceFeedTestnet: contracts.priceFeedTestnet.address,
      USBToken: contracts.USBToken.address,
      SortedTroves: contracts.sortedTroves.address,
      TroveManager: contracts.troveManager.address,
      StabilityPool: contracts.stabilityPool.address,
      ActivePool: contracts.activePool.address,
      DefaultPool: contracts.defaultPool.address,
      FunctionCaller: contracts.functionCaller.address,
    };
  }
  const SortedTroves = await ethers.getContractFactory("SortedTroves");
  const ActivePool = await ethers.getContractFactory("ActivePool");
  const DefaultPool = await ethers.getContractFactory("DefaultPool");
  const StabilityPool = await ethers.getContractFactory("StabilityPool");
  const TroveManager = await ethers.getContractFactory("TroveManager");
  const PriceFeed = await ethers.getContractFactory("PriceFeed");
  const USBToken = await ethers.getContractFactory("USBToken");
  const FunctionCaller = await ethers.getContractFactory("FunctionCaller");
  const BorrowerOperations = await ethers.getContractFactory(
    "BorrowerOperations"
  );
  const deploymentHelpers = require("../utils/truffleDeploymentHelpers.js");
  const connectContracts = deploymentHelpers.connectContracts;

  const sortedTroves = await SortedTroves.deploy();
  await sortedTroves.deployed();
  const activePool = await ActivePool.deploy();
  await activePool.deployed();
  const defaultPool = await DefaultPool.deploy();
  await defaultPool.deployed();
  const stabilityPool = await StabilityPool.deploy();
  await stabilityPool.deployed();
  const troveManager = await TroveManager.deploy();
  await troveManager.deployed();
  const priceFeed = await PriceFeed.deploy();
  await priceFeed.deployed();
  const functionCaller = await FunctionCaller.deploy();
  await functionCaller.deployed();
  const borrowerOperations = await BorrowerOperations.deploy();
  await borrowerOperations.deployed();
  const usbToken = await USBToken.deploy(
    troveManager.address,
    stabilityPool.address,
    borrowerOperations.address
  );
  await USBToken.deployed();

  const liquityContracts = [
    borrowerOperations,
    priceFeed,
    usbToken,
    sortedTroves,
    troveManager,
    activePool,
    stabilityPool,
    defaultPool,
    functionCaller,
  ];
  function getAddress(contracts) {
    contracts.forEach(element => {
      console.log(element.address);
      console.log("     ");
    });
  }
  //const liquityAddresses = getAddresses(liquityContracts);
  console.log("deploy_contracts.js - Deployed contract addresses: \n");
  getAddress(liquityContracts);
  console.log(
    `Name and Symbol of StableCoin is: ${await usbToken.name()} and ${await usbToken.symbol()}`
  );
  //console.log(liquityAddresses.address);
  console.log("\n");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
