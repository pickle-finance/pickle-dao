const hre = require("hardhat");
const {ethers} = require("hardhat");

const pickleAddr = "0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5";
const masterChefAddr = "0xbD17B1ce622d73bD438b9E658acA5996dc394b0d";

async function advanceNDays(days) {
  /**************** increase time by 7 days ******************* */
  console.log(`-- Advancing ${days} dyas --`);
  await network.provider.send("evm_increaseTime", [3600 * 24 * days])
  await network.provider.send("evm_mine") 
}

async function advanceSevenDays() {
  advanceNDays(7);
}

/**
 *
 * @param {contract} GaugeProxyV2
 * @param {array} lpAddr
 * @param {number} start
 * @param {number} end
 * @returns array
 */
async function distribute(GaugeProxyV2, lpAddr, start, end) {
  // await advanceSevenDays();
  console.log("This distribution is as per user's vote");
  console.log("Current Id => ", Number(await GaugeProxyV2.getCurrentPeriodId()));
  console.log("Distribution Id => ", Number(await GaugeProxyV2.distributionId()));
  await GaugeProxyV2.distribute(start, end);

  const pickle = await ethers.getContractAt("src/yield-farming/pickle-token.sol:PickleToken", pickleAddr);
  let rewards = [];

  lpAddr.forEach(async (lp) => {
    const gaugeAddr = await GaugeProxyV2.getGauge(lp);
    const rewardsGauge = await pickle.balanceOf(gaugeAddr);
    rewards.push(Number(rewardsGauge));
  });

  return rewards;
}

async function resetHardhatNetwork(){
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: "https://mainnet.infura.io/v3/a8b8321889b04a2a8f089680a4dd31b1",
        },
      },
    ],
  });
}

async function deployGaugeProxy(actor){

  masterChef = await ethers.getContractAt(
    "src/yield-farming/masterchef.sol:MasterChef",
    masterChefAddr,
    actor
  );
  masterChef.connect(actor);

  console.log("-- Deploying GaugeProxy v2 contract --");
    const gaugeProxyV2 = await ethers.getContractFactory(
      "/src/dill/gauge-proxies/gauge-proxy-v2.sol:GaugeProxyV2",
      actor
    );

    // getting timestamp
    const blockNumBefore = await ethers.provider.getBlockNumber();
    const blockBefore = await ethers.provider.getBlock(blockNumBefore);
    const timestampBefore = blockBefore.timestamp;

    const GaugeProxyV2 = await upgrades.deployProxy(
      gaugeProxyV2,
      [timestampBefore + 86400 * 7],
      {
        initializer: "initialize",
      }
    );
    await GaugeProxyV2.deployed();

    const mDILLAddr = await GaugeProxyV2.TOKEN();
    console.log("-- Adding mDILL to MasterChef --");

    populatedTx = await masterChef.populateTransaction.add(
      5000000,
      mDILLAddr,
      false
    );
    await actor.sendTransaction(populatedTx);
    
    const pidDill = (await masterChef.poolLength()) - 1;
    await GaugeProxyV2.setPID(pidDill);
    await GaugeProxyV2.deposit();
    return GaugeProxyV2;

}

async function deployGauge(token, actor, gaugeProxyAddress,rewardToken){
  console.log("Deploying gauges");
  const gauge = await ethers.getContractFactory("GaugeV2");
  const Gauge = await gauge.deploy(token, actor, gaugeProxyAddress);
  await Gauge.deployed();
  await Gauge.setRewardToken(rewardToken, gaugeProxyAddress);
  return Gauge;
}

async function unlockAccount(address){
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
}

module.exports = {
  advanceNDays,
  advanceSevenDays,
  distribute,
  resetHardhatNetwork,
  deployGaugeProxy,
  deployGauge,
  unlockAccount
};
