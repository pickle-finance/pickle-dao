const { ethers } = require("hardhat");


const tempPickleMain = "0x1Fcf02E6C31f3De71E7d164AC0e7fC3CaFDC0E38";
const CelerClientMainAddress = "0x90D538408E82cB99fEc827B0B881072cd4E488d3";
const CelerTokenMainAddress = "0xE0c8e1De45b2C7A07E884aB52Acd3dC92EED5c7e";
const CelerClientSideChain = "0x82cfA4a43AdBC656806Ef7837aaD00Ad44e24dD8";
const CelerTokenSideAddress = "0x839C479c8de1e1038deB2DCd1e4780f0C45Cd284";
const tempPickleSide = "0x7bd365550A2C4714c2C5Bdf2B1D9D35750FCeB32";

const main = async () => {
  /*
   set client and token peers side chain
   */
  console.log(" -- Setting peers on side chain --");
  const [deployer] = await ethers.getSigners();
  const CelerClient = await ethers.getContractAt("src/dill/celer/CelerClient.sol:CelerClient", CelerClientSideChain);

  await CelerClient.setClientPeers([4002], [CelerClientMainAddress]); //fantom
  await CelerClient.setTokenPeers(CelerTokenSideAddress, [4002], [CelerTokenMainAddress]); //CelerTOken

};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
