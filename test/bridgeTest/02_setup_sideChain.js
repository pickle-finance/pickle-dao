/* 
 **********************      SIDE CHAIN (rinkeby)    ******************************

*/

const { ethers, upgrades } = require("hardhat");
const tempPickle = "0x98BFfa7915Ce1f20C3a134F9d9E3a6E1436c0802";
const callProxyFTMTest = "0xD7c295E399CA928A3a14b01D760E794f1AdF8990";
const xyzToken = "0x5C8fB573708b3ecFBF2Aaf33Cc04872725cd8bf2";
const main = async () => {
  const [deployer] = await ethers.getSigners();

  const bal = await ethers.provider.getBalance(deployer.address);

  console.log("Deployer address => ", deployer.address);
  console.log("Deployer balance => ", Number(ethers.utils.formatEther(bal)));
  console.log("**********************************");

  /*
  Deploying any token
  */
  console.log("-- Deploying any token -- ");
  const anyToken = await ethers.getContractFactory(
    "/src/dill/anySwap/AnyswapV6ERC20.sol:AnyswapV6ERC20",
    deployer
  );
  const AnyToken = await anyToken.deploy(
    "ANY PICKLE",
    "AP",
    18,
    tempPickle,
    deployer.address
  ); // change underlying
  await AnyToken.deployed();
  console.log("Any Token Deployed at", AnyToken.address);
  /*
  Deploying anycallClient
    */
  console.log("-- Deploying anyCallClient --");
  const anyCallClient = await ethers.getContractFactory(
    "/src/dill/anySwap/AnyCallClient.sol:AnyswapTokenAnycallClient",
    deployer
  );
  const AnyCallClient = await anyCallClient.deploy(
    deployer.address,
    callProxyFTMTest,
    deployer.address
  ); // ******************* check parameters
  await AnyCallClient.deployed();
  console.log("AnyCallClient deployed at => ", AnyCallClient.address);

  /*
set minter
*/
  console.log("-- Setting minter --");
  const tx1 = await AnyToken.setMinter(AnyCallClient.address);
  tx1.wait();
  console.log("-- wait 10 seconds --");
  const delay = (ms) => new Promise((res) => setTimeout(res, ms));
  await delay(10000);
  console.log("-- Apply Minter --");
  const tx2 = await AnyToken.applyMinter();
  tx2.wait();

  /*
deploy temp erc20
*/
  const tempTokenERC20 = await ethers.getContractFactory(
    "/src/dill/mocks/test-erc20.sol:TestAnyswap",
    deployer
  );
  const gaugeToken = await tempTokenERC20.deploy("TEMP", "T");
  await gaugeToken.deployed();
  console.log("temp erc20 deployed at =>", gaugeToken.address);

  /*
  Deploying side chain gauge proxy
    */
  console.log("-- Deploying sidechain-gauge-proxy --");

  const sidechainGaugeProxy = await ethers.getContractFactory(
    "/src/dill/gauge-proxies/sidechain-gauge-proxy.sol:SidechainGaugeProxy",
    deployer
  );

  const SidechainGaugeProxy = await upgrades.deployProxy(
    sidechainGaugeProxy,
    [tempPickle, AnyCallClient.address, 1],
    {
      initializer: "initialize",
    }
  );
  await SidechainGaugeProxy.deployed();
  console.log("SidechainGaugeProxy deployed to:", SidechainGaugeProxy.address);
  console.log("**************************************************");

  /*
   Deploy Guage on sidechain
  */
  console.log("-- Deploying Gaugev2 contract --");
  const gaugeV2 = await ethers.getContractFactory(
    "/src/dill/gauges/GaugeV2.sol:GaugeV2",
    deployer
  );
  const GaugeV2 = await gaugeV2.deploy(gaugeToken.address, deployer.address);
  await GaugeV2.deployed();
  console.log("GaugeV2 deployed to:", GaugeV2.address);
  GaugeV2.setRewardToken(tempPickle, SidechainGaugeProxy.address);
  /*
  Register Gauge on sidechain gauge proxy on sidechain
  */
  await SidechainGaugeProxy.addGauge(gaugeToken.address, GaugeV2.address);

  console.log("-- Deploying XYZGaugev2 contract --");
  const XYZgaugeV2 = await ethers.getContractFactory(
    "/src/dill/gauges/GaugeV2.sol:GaugeV2",
    deployer
  );
  const XYZGaugeV2 = await XYZgaugeV2.deploy(xyzToken, deployer.address);
  await XYZGaugeV2.deployed();
  console.log("XYZGaugeV2 deployed to:", XYZGaugeV2.address);
  XYZGaugeV2.setRewardToken(tempPickle, SidechainGaugeProxy.address);
  /*
  Register Gauge on sidechain gauge proxy on sidechain
  */
  await SidechainGaugeProxy.addGauge(xyzToken, XYZGaugeV2.address);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
