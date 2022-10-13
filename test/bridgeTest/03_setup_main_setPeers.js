const { ethers } = require("hardhat");

const AnyTokenMainAddress = "0x1CF86D3737821f488C3f3BBC7818145190eA4A0F";
const anyCallClientMainChain = "0x9251F943286E2e1Ac8D3a09a9E5bD0E7DE766ba0";
const AnyTokenSideAddress = "0x406d59F3eb2484e06774252e30f3036cc46558AD";
const anyCallClientSideChain = "0xf929a39F1eD38CA0c9Cb28e29597420Ab471a655";


const sideChainGaugeProxyAddr = "0x44a435e8110f767Af960951BD19ff8590d0Cd8cA";
const tempPickleMainChain = "0x10359ea43A7c06A0ccE9F3F1F216961081Cd7Bd6";
const tempPickleSideChain = "0x5C8fB573708b3ecFBF2Aaf33Cc04872725cd8bf2";
// const gaugeProxyAddr = "0x30710519B625C253CA58e9dDE86580e002008E2E";
// const sidechainGaugeAddr = "0x229606Ce6d72730bd172f40192ac7752eC200175";
// const gaugeTokenAddr = "0xc1f695F52851D12D5a30cDf5D36B6a2027126147";


const main = async () => {

  const [deployer] = await ethers.getSigners();

  const bal = await ethers.provider.getBalance(deployer.address);

  console.log("Deployer address => ", deployer.address);
  console.log(
    "Deployer balance => ",
    Number(ethers.utils.formatEther(bal)),
  );
  console.log("**********************************");

  /*
  set client and token peers main chain
  */
  console.log(" -- Setting peers on main chain --");
  const AnyCallClient = await ethers.getContractAt(
    "/src/dill/anySwap/AnyCallClient.sol:AnyswapTokenAnycallClient",
    anyCallClientMainChain
      );
  // console.log("peers =>",await AnyCallClient.tokenPeers(AnyTokenMainAddress, 4));
  await AnyCallClient.setClientPeers([4002],[anyCallClientSideChain]); //fantom
  await AnyCallClient.setTokenPeers(AnyTokenMainAddress, [4002], [AnyTokenSideAddress]); //anytoken

  /*
Deploy Anyswap root gauge on mainnet
*/
console.log("-- Deploying AnyRootGauge --");
const anyRootGauge = await ethers.getContractFactory(
  "/src/dill/gauges/sidechains/AnyswapRootGauge.sol:AnyswapRootGauge",
  deployer
);
const AnyRootGauge = await anyRootGauge.deploy(
  anyCallClientMainChain,
  AnyTokenMainAddress,
  4002,
  sideChainGaugeProxyAddr
);
await AnyRootGauge.deployed();
console.log("AnyRootGauge deployed at =>", await AnyRootGauge.address);

// Set reward token
await AnyRootGauge.setRewardToken(tempPickleMainChain, deployer.address);

/*
Call addNewSideChain in gauge proxy
*/
// const GaugeProxyV2 = await ethers.getContractAt(
//   "/src/dill/gauge-proxies/gauge-proxy-v2.sol:GaugeProxyV2",
//   gaugeProxyAddr
// );
// console.log(" -- addNewSideChain --");
// await GaugeProxyV2.addNewSideChain("Rinkeby", 1, AnyRootGauge.address); // weight 1 ,root gauge hoga 
// console.log("_chainIdCounter =>", Number( await GaugeProxyV2._chainIdCounter()));
/*
 Register Gauge on gauge proxy v2
*/
// console.log(" -- Adding gauge --");
// await GaugeProxyV2.addGauge(gaugeTokenAddr, 1, sidechainGaugeAddr); // gauge token must be on side chain

};

main()
.then(() => process.exit(0))
.catch((error) => {
  console.error(error);
  process.exit(1);
});
