const { expect } = require("chai");
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");

const { advanceSevenDays, resetHardhatNetwork, deployGaugeProxy, deployGauge, unlockAccount } = require("./testHelper");

const governanceAddr = "0x9d074E37d408542FD38be78848e8814AFB38db17";
const masterChefAddr = "0xbD17B1ce622d73bD438b9E658acA5996dc394b0d";
const userAddr = "0xaCfE4511CE883C14c4eA40563F176C3C09b4c47C";
const pickleLP = "0xdc98556Ce24f007A5eF6dC1CE96322d65832A819";
const pickleAddr = "0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5";
const pyveCRVETH = "0x5eff6d166d66bacbc1bf52e2c54dd391ae6b1f48";
const dillHolder = "0x696A27eA67Cec7D3DA9D3559Cb086db0e814FeD3";
let GaugeProxyV2, userSigner, populatedTx, masterChef, Gauge1, Gauge2;

describe("Vote & Distribute", () => {
  before("Setting up gaugeProxyV2", async () => {
    await resetHardhatNetwork()
    /**
     *  sending gas cost to gov
     * */
    const signer = ethers.provider.getSigner();
    console.log("-- Sending gas cost to governance addr --");
    await signer.sendTransaction({
      to: governanceAddr,
      value: ethers.BigNumber.from("10000000000000000000"), // 1000 ETH
      data: undefined,
    });

    /** unlock governance account */
    await unlockAccount(governanceAddr);

    await unlockAccount(userAddr);

    const governanceSigner = ethers.provider.getSigner(governanceAddr);
    userSigner = ethers.provider.getSigner(userAddr);
    const signerAddress = await signer.getAddress()

    GaugeProxyV2 = await deployGaugeProxy(governanceSigner);
    Gauge1 = await deployGauge(pickleLP, signerAddress, GaugeProxyV2.address, pickleAddr);
    Gauge2 = await deployGauge(pyveCRVETH, signerAddress, GaugeProxyV2.address, pickleAddr);
    await advanceSevenDays();
  });
  beforeEach(async () => {
    console.log(
      "Current Id => ",
      Number(await GaugeProxyV2.getCurrentPeriodId())
    );
    console.log(
      "Distribution Id => ",
      Number(await GaugeProxyV2.distributionId())
    );
  });
  it("should add gauges successfully", async () => {

    console.log("-- Adding PICKLE LP Gauge --");
    await GaugeProxyV2.addGauge(pickleLP, 0, Gauge1.address);

    console.log("-- Adding pyveCRVETH Gauge --");
    await GaugeProxyV2.addGauge(pyveCRVETH, 0, Gauge2.address);

    await expect(GaugeProxyV2.addGauge(pickleLP, 0, Gauge1.address)).to.be.revertedWith(
      "GaugeProxy: exists"
    );

    console.log("tokens length", Number(await GaugeProxyV2.length()));
  });

  it("Should set delegate successfully", async () => {
    const gaugeProxyFromUser = GaugeProxyV2.connect(userAddr);
    populatedTx =
      await gaugeProxyFromUser.populateTransaction.setVotingDelegate(
        governanceAddr,
        2,
        false
      );
    await userSigner.sendTransaction(populatedTx);
  });

  it("delegate vote should fail as votes count does not match weights count", async () => {
    /** here gov will vote on behalf of user */
    await expect(
      GaugeProxyV2.voteFor([pickleLP, pyveCRVETH], [6000000], 0, 1)
    ).to.be.revertedWith("GaugeProxy: token votes count does not match weights count");
  });

  it("delegate should vote successfully", async () => {
    /** here gov will vote on behalf of user */
    GaugeProxyV2.voteFor([pickleLP, pyveCRVETH], [4000000, 6000000], 0, 1);
  });

  it("successfully Distribute after advancing 7 days", async () => {
    await advanceSevenDays();
    await GaugeProxyV2.distribute(0, 2);
    const pickleGaugeAddr = await GaugeProxyV2.getGauge(pickleLP);
    const yvecrvGaugeAddr = await GaugeProxyV2.getGauge(pyveCRVETH);

    const pickle = await ethers.getContractAt(
      "src/yield-farming/pickle-token.sol:PickleToken",
      pickleAddr
    );

    const pickleRewards = await pickle.balanceOf(pickleGaugeAddr.gaugeAddress);
    console.log("rewards to Pickle gauge => ", pickleRewards.toString());

    const yvecrvRewards = await pickle.balanceOf(yvecrvGaugeAddr.gaugeAddress);
    console.log("rewards to pyveCRV gauge => ", yvecrvRewards.toString());

  });

  it("delegate should vote again successfully ", async () => {
    /** here gov will vote on behalf of user */
    await GaugeProxyV2.voteFor(
      [pickleLP, pyveCRVETH],
      [4000000, 6000000],
      0,
      1
    );
  });
  it("user must successfully overwrite his votes after delegate has voted ", async () => {
    const gaugeProxyFromUser = GaugeProxyV2.connect(userAddr);
    populatedTx = await gaugeProxyFromUser.populateTransaction.vote(
      [pickleLP, pyveCRVETH],
      [6000000, 4000000],
      {
        gasLimit: 900000,
      }
    );
    await userSigner.sendTransaction(populatedTx);
  });

  it("Successfully Distribute PICKLE to gauges advancing 7 days", async () => {
    await advanceSevenDays();
    await GaugeProxyV2.distribute(0, 2);
    const pickleGaugeAddr = await GaugeProxyV2.getGauge(pickleLP);
    const yvecrvGaugeAddr = await GaugeProxyV2.getGauge(pyveCRVETH);

    const pickle = await ethers.getContractAt(
      "src/yield-farming/pickle-token.sol:PickleToken",
      pickleAddr
    );

    const pickleRewards = await pickle.balanceOf(pickleGaugeAddr.gaugeAddress);
    console.log("rewards to Pickle gauge => ", pickleRewards.toString());

    const yvecrvRewards = await pickle.balanceOf(yvecrvGaugeAddr.gaugeAddress);
    console.log("rewards to pyveCRV gauge => ", yvecrvRewards.toString());
  });

  it("Should reset delegate successfully and again reset to indefinite", async () => {
    const gaugeProxyFromUser = GaugeProxyV2.connect(userAddr);
    populatedTx =
      await gaugeProxyFromUser.populateTransaction.setVotingDelegate(
        dillHolder,
        2,
        false
      );
    await userSigner.sendTransaction(populatedTx);

    populatedTx =
      await gaugeProxyFromUser.populateTransaction.setVotingDelegate(
        dillHolder,
        2,
        true
      );
    await userSigner.sendTransaction(populatedTx);
  });
});
