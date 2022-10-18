const { ethers } = require("hardhat");

const tempPickleMain = "0x1Fcf02E6C31f3De71E7d164AC0e7fC3CaFDC0E38";
const CelerClientMainAddress = "0x32a704Dba875a51c814CFF5DbdB6C584453480cE";
const CelerTokenMainAddress = "0xE0c8e1De45b2C7A07E884aB52Acd3dC92EED5c7e";
const sidechainGaugeProxyAddress = "0x8fD50D436Fdc9Fd5423f7E11874f44a7964C53da";
const CelerRootGaugeAddress = "0xEAFf63bD89D6126Db450951929259F446E4335c5";

const main = async () => {
    const [deployer] = await ethers.getSigners()
    // console.log("-- Deploying mainchain-root-gauge --");

    // const celerRootGauge = await ethers.getContractFactory("CelerRootGauge");

    // const CelerRootGauge = await celerRootGauge.deploy(CelerClientMainAddress, CelerTokenMainAddress, 5, sidechainGaugeProxy)
    // await CelerRootGauge.deployed();
    // console.log("CelerRootGauge deployed to:", CelerRootGauge.address);

    const CelerRootGauge = await ethers.getContractAt("src/dill/Celer/CelerRootGauge.sol:CelerRootGauge", CelerRootGaugeAddress);
    console.log("CelerRootGauge listening at :", CelerRootGauge.address);

    console.log("setting reward token");
    await CelerRootGauge.setRewardToken(tempPickleMain, deployer.address);
    


    console.log("**************************************************");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });