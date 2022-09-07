/* 
 **********************      MAIN CHAIN (fantom)    ******************************
1. deploy any token
2. deploy bridge (anycall client) => callproxy 0xC10Ef9F491C9B59f936957026020C321651ac078
*/

const { ethers, upgrades } = require("hardhat");
const tempPickle = "0x10359ea43A7c06A0ccE9F3F1F216961081Cd7Bd6";
const callProxyRinkeby = "0x273a4fFcEb31B8473D51051Ad2a2EdbB7Ac8Ce02";


const main = async () => {
  const [deployer] = await ethers.getSigners();

  const bal = await ethers.provider.getBalance(deployer.address);

  console.log("Deployer address => ", deployer.address);
  console.log(
    "Deployer balance => ",
    Number(ethers.utils.formatEther(bal))
  );
  console.log("**********************************");

  /*
  Deploying any token
  */
  console.log("-- Deploying any token -- ");
  const anyToken = await ethers.getContractFactory(
    "/src/dill/anySwap/AnyswapV6ERC20.sol:AnyswapV6ERC20",
    deployer
  );
  const AnyToken = await anyToken.deploy("ANY PICKLE", "AP", 18, tempPickle, deployer.address); // change underlying
  await AnyToken.deployed();
  console.log("Any Token deployed at", AnyToken.address);

  /*
  Deploying anycallClient
    */
  console.log("-- Deploying anyCallClient --");
  const anyCallClient = await ethers.getContractFactory(
    "/src/dill/anySwap/AnyCallClient.sol:AnyswapTokenAnycallClient",
    deployer
  );
  const AnyCallClient = await anyCallClient.deploy(deployer.address, callProxyRinkeby, deployer.address); // ******************* check parameters
  await AnyCallClient.deployed();
  console.log("AnyCallClient deployed at => ", AnyCallClient.address);


  /*
  set minter
  */
  console.log("-- Setting Minter --");
  await AnyToken.setMinter(AnyCallClient.address);
  const delay = ms => new Promise(res => setTimeout(res, ms));
  await delay(10000);
  console.log("-- Apply Minter --");
  await AnyToken.applyMinter();


    /*
  Deploying gaugeProxyV2
    */
  // console.log("-- Deploying GaugeProxyV2 --");
  // const blockNumBefore = await ethers.provider.getBlockNumber();
  // const blockBefore = await ethers.provider.getBlock(blockNumBefore);
  // const timestampBefore = blockBefore.timestamp;
  
  // const gaugeProxyV2 = await ethers.getContractFactory(
  //   "/src/dill/gauge-proxies/gauge-proxy-v2.sol:GaugeProxyV2",
  //   deployer
  // );
  
  // const GaugeProxyV2 = await upgrades.deployProxy(
  //   gaugeProxyV2,
  //   [timestampBefore],
  //   {
  //     initializer: "initialize",
  //   }
  // );
  // await GaugeProxyV2.deployed();
  // console.log("GaugeProxyV2 deployed to:", GaugeProxyV2.address);

  console.log("**************************************************");
  
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
  
