const { expect } = require("chai");
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");

const { advanceSevenDays } = require("./testHelper");

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
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://mainnet.infura.io/v3/api",
          },
        },
      ],
    });
    /**
     *  sending gas cost to gov
     * */
    const signer = ethers.provider.getSigner();
    // console.log("-- Sending gas cost to governance addr --");
    // await signer.sendTransaction({
    //   to: governanceAddr,
    //   value: ethers.BigNumber.from("10000000000000000000"), // 1000 ETH
    //   data: undefined,
    // });

    /** unlock governance account */
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [governanceAddr],
    });

    const governanceSigner = ethers.provider.getSigner(governanceAddr);
    userSigner = ethers.provider.getSigner(userAddr);
    masterChef = await ethers.getContractAt(
      "src/yield-farming/masterchef.sol:MasterChef",
      masterChefAddr,
      governanceSigner
    );
    masterChef.connect(governanceSigner);

    /** Deploy gaugeProxyV2 */
    console.log("-- Deploying GaugeProxy v2 contract --");
    const gaugeProxyV2 = await ethers.getContractFactory(
      "/src/dill/gauge-proxies/gauge-proxy-v2.sol:GaugeProxyV2",
      governanceSigner
    );
    // getting timestamp
    const blockNumBefore = await ethers.provider.getBlockNumber();
    const blockBefore = await ethers.provider.getBlock(blockNumBefore);
    const timestampBefore = blockBefore.timestamp;

    GaugeProxyV2 = await upgrades.deployProxy(gaugeProxyV2, [timestampBefore], {
      initializer: "initialize",
    });
    await GaugeProxyV2.deployed();

    console.log("GaugeProxyV2 deployed to:", GaugeProxyV2.address);

    const mDILLAddr = await GaugeProxyV2.TOKEN();
    console.log("-- Adding mDILL to MasterChef --");
    let populatedTx;
    populatedTx = await masterChef.populateTransaction.add(
      5000000,
      mDILLAddr,
      false
    );
    await governanceSigner.sendTransaction(populatedTx);


    console.log("Deploying gauges");
    let signerAddress = await signer.getAddress()

    const gauge1 = await ethers.getContractFactory("GaugeV2");
    Gauge1 = await gauge1.deploy(pickleLP, signerAddress, GaugeProxyV2.address);
    await Gauge1.deployed();
    await Gauge1.setRewardToken(pickleAddr, GaugeProxyV2.address);

    const gauge2 = await ethers.getContractFactory("GaugeV2");
    Gauge2 = await gauge2.deploy(pyveCRVETH, signerAddress, GaugeProxyV2.address);
    await Gauge2.deployed();
    await Gauge2.setRewardToken(pickleAddr, GaugeProxyV2.address);

    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [userAddr],
    });
    const pidDill = (await masterChef.poolLength()) - 1;
    await GaugeProxyV2.setPID(pidDill);
    await GaugeProxyV2.deposit();
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
        gasLimit: 9000000,
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
