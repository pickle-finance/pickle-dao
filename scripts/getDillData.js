const { ethers } = require("ethers");
 // temp file to store dill balances, in future fetch from DB
 // change name to => npx hardhat run scripts/getDillData.js --network hardhat > YourFileName.json
const data = require("../DILLBalances.json");
const { dillSidechainAddress } = require("./config");

const pushToSidechainContract = async () => {
  let provider = ethers.providers.getDefaultProvider();

  const dillSideChainContract = new ethers.Contract(
    dillSidechainAddress,
    "/src/dill/DillSideChain.sol:DillSideChain",
    provider
  );

  let users = new Array();
  let values = new Array();

  // create arrays from fetched Json file
  for (let i = 0; i < data.length; i++) {
    users.push(data[i][0]);
    values.push(data[i][1].balance);
  }

  await dillSideChainContract.setUserData(users, values);
};

const main = async () => {
  try {
    await pushToSidechainContract();
  } catch (error) {
    console.error(error);
  }
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
