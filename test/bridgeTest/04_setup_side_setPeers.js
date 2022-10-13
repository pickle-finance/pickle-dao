const { ethers } = require("hardhat");


const AnyTokenMainAddress = "0x1CF86D3737821f488C3f3BBC7818145190eA4A0F";
const anyCallClientMainChain = "0x9251F943286E2e1Ac8D3a09a9E5bD0E7DE766ba0";
const AnyTokenSideAddress = "0x406d59F3eb2484e06774252e30f3036cc46558AD";
const anyCallClientSideChain = "0xf929a39F1eD38CA0c9Cb28e29597420Ab471a655";

const main = async () => {
 /*
  set client and token peers side chain
  */
  console.log(" -- Setting peers on side chain --");
  const AnyCallClient = await ethers.getContractAt(
    "/src/dill/anySwap/AnyCallClient.sol:AnyswapTokenAnycallClient",
    anyCallClientSideChain
      );
  await AnyCallClient.setClientPeers([4],[anyCallClientMainChain]); 
  await AnyCallClient.setTokenPeers(AnyTokenSideAddress, [4], [AnyTokenMainAddress]); 
  
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
