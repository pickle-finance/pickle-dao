const {web3} = require("hardhat");
const {ethers, upgrades} = require("hardhat");
const main = async () => {
    const governanceAddr = "0x9d074E37d408542FD38be78848e8814AFB38db17";
    const masterChefAddr = "0xbD17B1ce622d73bD438b9E658acA5996dc394b0d";
  const [deployer] = await ethers.getSigners();

  const bal = await ethers.provider.getBalance(deployer.address);
  const gaugeMiddleware = await ethers.getContractFactory(
    "/src/dill/gauge-middleware.sol:GaugeMiddleware"
  );
  const GaugeMiddleware = await upgrades.deployProxy(gaugeMiddleware, [masterChefAddr, governanceAddr])
await GaugeMiddleware.deployed();

  console.log("deployed at", GaugeMiddleware.address);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
