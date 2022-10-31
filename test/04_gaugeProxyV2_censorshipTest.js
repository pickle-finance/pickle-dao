const { expect } = require("chai");
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
// const {describe, it, before} = require("mocha");
const { advanceSevenDays, resetHardhatNetwork, deployGaugeProxy, deployGauge, unlockAccount } = require("./testHelper");
// const dillAddr = "0xbBCf169eE191A1Ba7371F30A1C344bFC498b29Cf";
const governanceAddr = "0x9d074E37d408542FD38be78848e8814AFB38db17";
const masterChefAddr = "0xbD17B1ce622d73bD438b9E658acA5996dc394b0d";
const userAddr = "0xaCfE4511CE883C14c4eA40563F176C3C09b4c47C";
const pickleLP = "0xdc98556Ce24f007A5eF6dC1CE96322d65832A819";
const pickleAddr = "0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5";
const pyveCRVETH = "0x5eff6d166d66bacbc1bf52e2c54dd391ae6b1f48";
const dillHolder1Addr = "0x9d074e37d408542fd38be78848e8814afb38db17";
const dillHolder2Addr = "0x5c4D8CEE7dE74E31cE69E76276d862180545c307";

let GaugeProxyV2, userSigner, populatedTx, masterChef, pickle, Gauge1, Gauge2;

describe("vote & distribute", () => {
  before("setting up gaugeProxyV2", async () => {

    await resetHardhatNetwork();
    /**
     *  sending gas cost to gov
     * */
    const signer = ethers.provider.getSigner();

    console.log((await signer.getBalance()).toString());

    console.log("-- Sending gas cost to governance addr --");
    await signer.sendTransaction({
      to: governanceAddr,
      value: ethers.BigNumber.from("10000000000000000000"),
      data: undefined,
    });

    await signer.sendTransaction({
      to: dillHolder1Addr,
      value: ethers.BigNumber.from("1000000000000000000"),
      data: undefined,
    });
    await signer.sendTransaction({
      to: dillHolder2Addr,
      value: ethers.BigNumber.from("1000000000000000000"),
      data: undefined,
    });
    /** unlock governance account */
    await unlockAccount(governanceAddr);
    /** unlock dill holders accounts */
    await unlockAccount(userAddr);
    await unlockAccount(dillHolder1Addr);
    await unlockAccount(dillHolder2Addr);

    const governanceSigner = ethers.provider.getSigner(governanceAddr);
    userSigner = ethers.provider.getSigner(userAddr);
    const signerAddress = await signer.getAddress()

    GaugeProxyV2 = await deployGaugeProxy(governanceSigner);
    Gauge1 = await deployGauge(pickleLP, signerAddress, GaugeProxyV2.address, pickleAddr);
    Gauge2 = await deployGauge(pyveCRVETH, signerAddress, GaugeProxyV2.address, pickleAddr);

    pickle = await ethers.getContractAt(
      "src/yield-farming/pickle-token.sol:PickleToken",
      pickleAddr
    );
    // dill = await ethers.getContractAt("src/DillABI:dillAbi", dillAddr);
    // console.log(await dill.totalSupply());
  });

  it.only("should add gauges successfully", async () => {
    console.log("-- Adding PICKLE LP Gauge --");
    await GaugeProxyV2.addGauge(pickleLP, 0, Gauge1.address);

    console.log("-- Adding pyveCRVETH Gauge --");
    await GaugeProxyV2.addGauge(pyveCRVETH, 0, Gauge2.address);

    await expect(GaugeProxyV2.addGauge(pickleLP, 0, Gauge1.address)).to.be.revertedWith(
      "GaugeProxy: exists"
    );

    console.log("tokens length", Number(await GaugeProxyV2.length()));
  });

  it.only("should vote successfully with -ve votes(first voting)", async () => {
    await advanceSevenDays();
    console.log("-- Voting on LP Gauge with negative weight --");
    const gaugeProxyFromUser = GaugeProxyV2.connect(userAddr);
    populatedTx = await gaugeProxyFromUser.populateTransaction.vote(
      [pickleLP, pyveCRVETH],
      [-4000000, 6000000],
      {
        gasLimit: 900000,
      }
    );
    await userSigner.sendTransaction(populatedTx);
    console.log(
      "currentId",
      (await GaugeProxyV2.getCurrentPeriodId()).toString()
    );
    console.log("ID:@1", await GaugeProxyV2.weights(1, pickleLP));
    console.log("ID:@1", await GaugeProxyV2.weights(1, pyveCRVETH));
  });

  it.only("successfully Distribute(initial) PICKLE to gauges advancing 7 days", async () => {
    await advanceSevenDays();
    console.log(
      "currentId",
      (await GaugeProxyV2.getCurrentPeriodId()).toString()
    );
    console.log(
      "distributionId",
      (await GaugeProxyV2.distributionId()).toString()
    );

    await GaugeProxyV2.distribute(0, 2);

    const pickleGaugeAddr = await GaugeProxyV2.getGauge(pickleLP);
    const yvecrvGaugeAddr = await GaugeProxyV2.getGauge(pyveCRVETH);

    const pickleRewards = await pickle.balanceOf(pickleGaugeAddr.gaugeAddress);
    console.log("rewards to Pickle gauge", pickleRewards.toString());

    const yvecrvRewards = await pickle.balanceOf(yvecrvGaugeAddr.gaugeAddress);
    console.log("rewards to pyveCRV gauge", yvecrvRewards.toString());

    console.log(
      "-- pickleLP gauge with -ve weight ",
      Number(await GaugeProxyV2.gaugeWithNegativeWeight(pickleGaugeAddr.gaugeAddress))
    );
    console.log(
      "-- pyveCRVETH gauge with -ve weight ",
      Number(await GaugeProxyV2.gaugeWithNegativeWeight(yvecrvGaugeAddr.gaugeAddress))
    );
  });

  it.only("Should test total aggregate voting successfully", async () => {
    await advanceSevenDays();
    console.log(
      "currentId--2",
      (await GaugeProxyV2.getCurrentPeriodId()).toString()
    );
    const dillHolder1 = ethers.provider.getSigner(dillHolder1Addr);
    const dillHolder2 = ethers.provider.getSigner(dillHolder2Addr);
    // GaugeProxyV2 by user
    const GaugeV2By1 = GaugeProxyV2.connect(dillHolder1);
    const GaugeV2By2 = GaugeProxyV2.connect(dillHolder2);
    // vote by Luffy
    console.log("-- Voting on LP Gauge with by Luffy --");
    populatedTx = await GaugeV2By1.populateTransaction.vote(
      [pickleLP, pyveCRVETH],
      [4000000, -1000000],
      {
        gasLimit: 900000,
      }
    );
    await dillHolder1.sendTransaction(populatedTx);
    console.log("ID:@3", await GaugeProxyV2.weights(3, pickleLP));
    console.log("ID:@3------", await GaugeProxyV2.weights(3, pyveCRVETH));

    // vote by Zoro
    console.log("-- Voting on LP Gauge with by Zoro --");
    populatedTx = await GaugeV2By2.populateTransaction.vote(
      [pickleLP, pyveCRVETH],
      [4000000, -4000000],
      {
        gasLimit: 900000,
      }
    );
    await dillHolder2.sendTransaction(populatedTx);

    console.log("ID:@3", await GaugeProxyV2.weights(3, pickleLP));
    console.log("ID:@3------", await GaugeProxyV2.weights(3, pyveCRVETH));

    await advanceSevenDays();
    //3
    console.log("-- Voting on LP Gauge with negative weight by Zoro -- 3");

    console.log(
      "currentId",
      (await GaugeProxyV2.getCurrentPeriodId()).toString()
    );
    populatedTx = await GaugeV2By2.populateTransaction.vote(
      [pickleLP, pyveCRVETH],
      [4000000, -1000000],
      {
        gasLimit: 900000,
      }
    );
    await dillHolder2.sendTransaction(populatedTx);

    console.log("ID:@4", await GaugeV2By2.weights(4, pickleLP));
    console.log("ID:@4", await GaugeV2By2.weights(4, pyveCRVETH));
    await advanceSevenDays();

    //3
    console.log("-- Voting on LP Gauge with negative weight by Zoro -- 4");
    console.log(
      "currentId",
      (await GaugeProxyV2.getCurrentPeriodId()).toString()
    );
    populatedTx = await GaugeV2By2.populateTransaction.vote(
      [pickleLP, pyveCRVETH],
      [4000000, -1000000],
      {
        gasLimit: 900000,
      }
    );
    await dillHolder2.sendTransaction(populatedTx);

    console.log("ID:@5", await GaugeProxyV2.weights(5, pickleLP));
    console.log("ID:@5------", await GaugeProxyV2.weights(5, pyveCRVETH));


    await advanceSevenDays();

    //4
    console.log("-- Voting on LP Gauge with negative weight by Zoro -- 5");
    console.log(
      "currentId",
      (await GaugeProxyV2.getCurrentPeriodId()).toString()
    );
    populatedTx = await GaugeV2By2.populateTransaction.vote(
      [pickleLP, pyveCRVETH],
      [4000000, -1000000],
      {
        gasLimit: 900000,
      }
    );
    await dillHolder2.sendTransaction(populatedTx);

    console.log("ID:@6", await GaugeProxyV2.weights(6, pickleLP));
    console.log("ID:@6------", await GaugeProxyV2.weights(6, pyveCRVETH));

    await advanceSevenDays();

    //5
    console.log("-- Voting on LP Gauge with negative weight by Zoro -- 6");
    console.log(
      "currentId",
      (await GaugeProxyV2.getCurrentPeriodId()).toString()
    );
    populatedTx = await GaugeV2By2.populateTransaction.vote(
      [pickleLP, pyveCRVETH],
      [4000000, -1000000],
      {
        gasLimit: 900000,
      }
    );
    await dillHolder2.sendTransaction(populatedTx);

    console.log("ID:@7", await GaugeProxyV2.weights(7, pickleLP));
    console.log("ID:@7------", await GaugeProxyV2.weights(7, pyveCRVETH));

    await advanceSevenDays();
    console.log(
      "currentId",
      (await GaugeProxyV2.getCurrentPeriodId()).toString()
    );
    console.log(
      "distributionId",
      (await GaugeProxyV2.distributionId()).toString()
    );

    const pickleGaugeAddr = await GaugeProxyV2.getGauge(pickleLP);
    const yvecrvGaugeAddr = await GaugeProxyV2.getGauge(pyveCRVETH);

    const pickleRewards = await pickle.balanceOf(pickleGaugeAddr.gaugeAddress);
    console.log("rewards to Pickle gauge", pickleRewards.toString());

    const yvecrvRewards = await pickle.balanceOf(yvecrvGaugeAddr.gaugeAddress);
    console.log("rewards to pyveCRV gauge", yvecrvRewards.toString());
  });
  it.only("Should successfully test delist gauge", async () => {

    const dillHolder2 = ethers.provider.getSigner(dillHolder2Addr);
    await expect(GaugeProxyV2.delistGauge(masterChefAddr)).to.be.revertedWith(
      "GaugeProxy: !exists"
    );
    await expect(
      GaugeProxyV2.connect(dillHolder2).delistGauge(pyveCRVETH)
    ).to.be.revertedWith("Operation allowed by only governance");
    await expect(GaugeProxyV2.delistGauge(pyveCRVETH)).to.be.revertedWith(
      "GaugeProxy: all distributions completed"
    );
    console.log(
      "currentId",
      (await GaugeProxyV2.getCurrentPeriodId()).toString()
    );
    console.log(
      "distributionId",
      (await GaugeProxyV2.distributionId()).toString()
    );
    console.log("-- Distributing 6 times -- ");
    await GaugeProxyV2.distribute(0, 2);
    await GaugeProxyV2.distribute(0, 2);
    await GaugeProxyV2.distribute(0, 2);
    await GaugeProxyV2.distribute(0, 2);
    await GaugeProxyV2.distribute(0, 2);
    await GaugeProxyV2.distribute(0, 2);


    await expect(GaugeProxyV2.delistGauge(pickleLP)).to.be.revertedWith(
      "GaugeProxy: censors < 5"
    );
    console.log(
      "currentId",
      (await GaugeProxyV2.getCurrentPeriodId()).toString()
    );
    console.log(
      "distributionId",
      (await GaugeProxyV2.distributionId()).toString()
    );


    const pickleGaugeAddr = await GaugeProxyV2.getGauge(pickleLP);
    const yvecrvGaugeAddr = await GaugeProxyV2.getGauge(pyveCRVETH);

    const pickleRewards = await pickle.balanceOf(pickleGaugeAddr.gaugeAddress);
    console.log("rewards to Pickle gauge", pickleRewards.toString());

    const yvecrvRewards = await pickle.balanceOf(yvecrvGaugeAddr.gaugeAddress);
    console.log("rewards to pyveCRV gauge", yvecrvRewards.toString());

    console.log(
      "-- pickleLP gauge with -ve weight ",
      Number(await GaugeProxyV2.gaugeWithNegativeWeight(pickleGaugeAddr.gaugeAddress))
    );
    console.log(
      "-- pyveCRVETH gauge with -ve weight ",
      Number(await GaugeProxyV2.gaugeWithNegativeWeight(yvecrvGaugeAddr.gaugeAddress))
    );

    console.log("-- Removing gauge with -ve aggregate voting > 5 --");
    await GaugeProxyV2.delistGauge(pyveCRVETH);
  });
});
