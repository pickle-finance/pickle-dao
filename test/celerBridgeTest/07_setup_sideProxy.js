
const CelerClientSideChain = "0x78b6A8837e27f84879118bCc27a6c0014E27209F";
const CelerTokenSideAddress = "0x839C479c8de1e1038deB2DCd1e4780f0C45Cd284";
const tempPickleSide = "0x7bd365550A2C4714c2C5Bdf2B1D9D35750FCeB32";
const sidechainGaugeProxyAddress = "0x8fD50D436Fdc9Fd5423f7E11874f44a7964C53da";
const CelerRootGaugeAddress = "0xEAFf63bD89D6126Db450951929259F446E4335c5";



const main = async () => {

    console.log("-- Deploying sidechain-gauge-proxy --");

    const sidechainGaugeProxy = await ethers.getContractFactory("SidechainGaugeProxy");
  
    const SidechainGaugeProxy = await upgrades.deployProxy(
      sidechainGaugeProxy,
      [tempPickleSide, CelerClientSideChain, 1],
      {
        initializer: "initialize",
      }
    );
    await SidechainGaugeProxy.deployed();
    console.log("SidechainGaugeProxy deployed to:", SidechainGaugeProxy.address);
    console.log("**************************************************");
}
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });

