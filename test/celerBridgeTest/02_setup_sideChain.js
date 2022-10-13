/* 
 **********************      SIDE CHAIN (goerli)    ******************************

*/

const { ethers } = require("hardhat");
const tempPickleMain = "0x1Fcf02E6C31f3De71E7d164AC0e7fC3CaFDC0E38";
const CelerClientMainAddress = "0x90D538408E82cB99fEc827B0B881072cd4E488d3";
const CelerTokenMainAddress = "0xE0c8e1De45b2C7A07E884aB52Acd3dC92EED5c7e";
const CelerClientSideChain = "0x82cfA4a43AdBC656806Ef7837aaD00Ad44e24dD8";
const CelerTokenSideAddress = "0x839C479c8de1e1038deB2DCd1e4780f0C45Cd284";
const tempPickleSide = "0x7bd365550A2C4714c2C5Bdf2B1D9D35750FCeB32";

const main = async () => {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying Celer Token");
  const celerToken = await ethers.getContractFactory("CelerERC20");
  const CelerToken = await celerToken.deploy("ANY PICKLE", "AP", 18, tempPickleSide, deployer.address); // change underlying
  await CelerToken.deployed();
  console.log("Celer token deployed : ", CelerToken.address);

  const celerClient = await ethers.getContractFactory("CelerClient");
  const CelerClient = await celerClient.deploy("0xF25170F86E4291a99a9A560032Fe9948b8BcFBB2");
  await CelerClient.deployed();
  console.log("Celer deployed at :", CelerClient.address);

  console.log("-- Setting Minter --");
  await CelerToken.setMinter(CelerClient.address);
  const delay = ms => new Promise(res => setTimeout(res, ms));
  await delay(10000);
  console.log("-- Apply Minter --");
  await CelerToken.applyMinter();

  
const tempPickle = await ethers.getContractAt(
  "src/dill/celer/TempPickle.sol:TempPickle",
  tempPickleSide
);

await tempPickle.transfer(CelerToken.address, 100000);
};


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
