const { ethers } = require("hardhat");
// send pickle to anytoken on sidechain
// send pickle to deployer address i.e. admin
const main = async () => {
  const [deployer] = await ethers.getSigners();
  // const tempPickle = await ethers.getContractFactory(
  //     "/src/dill/gauge-proxies/TempPickle.sol:TempPickle",
  //     deployer
  //   );
  //   const TempPickle = await tempPickle.deploy(ethers.utils.parseEther("100000"));
  //   await TempPickle.deployed();
  //   console.log("TempPickle deployed at =>", TempPickle.address);

  const tempPickleSide = "0x5C8fB573708b3ecFBF2Aaf33Cc04872725cd8bf2";
// const AnyTokenSideAddress = "0x380056c861CdF4F3C5e0281Fcc43154E5E83b2E6";
// const AnyTokenSideChain = "0x99a3e3a2C6d2c2D6A54E2123C16126910A150135";
  // // const AnyTokenMainAddress = "0x31FC5da9397B3f605ac2C185937cEFBBC53372Fc";
  const tempPickleMain = "0x5865228c6b543CE8e3883890fCCA81f3178b5dDa";

  const tempPickle = await ethers.getContractAt(
    "/src/yield-farming/pickle-token.sol:PickleToken",
    "0x98BFfa7915Ce1f20C3a134F9d9E3a6E1436c0802"
  );
  console.log("-- Depositing funds in AnyToken on SideChain --");
  await tempPickle.transfer(
   "0x406d59F3eb2484e06774252e30f3036cc46558AD",
    ethers.utils.parseEther("20000")
  );
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
