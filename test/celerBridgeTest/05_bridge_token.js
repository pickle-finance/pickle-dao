// ftm test => rinkeby
const { ethers } = require("hardhat");

const tempPickleMain = "0x1Fcf02E6C31f3De71E7d164AC0e7fC3CaFDC0E38";
const CelerClientMainAddress = "0x32a704Dba875a51c814CFF5DbdB6C584453480cE";
const CelerTokenMainAddress = "0xE0c8e1De45b2C7A07E884aB52Acd3dC92EED5c7e";
const CelerClientSideChain = "0x78b6A8837e27f84879118bCc27a6c0014E27209F";
const CelerTokenSideAddress = "0x839C479c8de1e1038deB2DCd1e4780f0C45Cd284";
const tempPickleSide = "0x7bd365550A2C4714c2C5Bdf2B1D9D35750FCeB32";
const sidechainGaugeProxyAddress = "0x8fD50D436Fdc9Fd5423f7E11874f44a7964C53da";
const CelerRootGaugeAddress = "0xEAFf63bD89D6126Db450951929259F446E4335c5";


const main = async () => {
    // const TempPickleMain = await ethers.getContractAt(
    //     "src/dill/Celer/TempPickle.sol:TempPickle",
    //     tempPickleMain
    // );
    
    // console.log("Approve reward token to root gauge");
    // await TempPickleMain.approve(CelerRootGaugeAddress, 1000000);

    // const CelerRootGauge = await ethers.getContractAt("src/dill/Celer/CelerRootGauge.sol:CelerRootGauge", CelerRootGaugeAddress);
    // console.log("CelerRootGauge listening at :", CelerRootGauge.address);

    // console.log("Call notify reward of celerRootGauge");
    // const foo = await CelerRootGauge.notifyRewardAmount(
    //     tempPickleMain,
    //     100,
    //     [],
    //     1,
    //     {
    //       value: ethers.utils.parseEther("0.005"),
    //       gasLimit: 900000,
    //     }
    //   );

    const sidechainGaugeProxy = await ethers.getContractAt(
        "/src/dill/gauge-proxies/sidechain-gauge-proxy.sol:SidechainGaugeProxy",
        sidechainGaugeProxyAddress
      );
    console.log("side Chain GaugeProxy listening at :" , sidechainGaugeProxy.address);

    const TempPickleSide = await ethers.getContractAt(
        "src/dill/Celer/TempPickle.sol:TempPickle",
        tempPickleSide
    );

    console.log("Balance of sideChain",await TempPickleSide.balanceOf(sidechainGaugeProxy.address));
    console.log("Balance of SideCelerERC20",await TempPickleSide.balanceOf(CelerTokenSideAddress));


    

};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
