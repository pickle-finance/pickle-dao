const { advanceSevenDays, resetHardhatNetwork, deployGaugeProxy, deployGauge, unlockAccount } = require("./testHelper");
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const { expect } = require("chai");
const { Signer } = require("ethers");

const governanceAddr = "0x9d074E37d408542FD38be78848e8814AFB38db17";
const masterChefAddr = "0xbD17B1ce622d73bD438b9E658acA5996dc394b0d";
const userAddr = "0xaCfE4511CE883C14c4eA40563F176C3C09b4c47C";
const pickleLP = "0xdc98556Ce24f007A5eF6dC1CE96322d65832A819";
const pickleAddr = "0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5";
const pyveCRVETH = "0x5eff6d166d66bacbc1bf52e2c54dd391ae6b1f48";
const zeroAddr = "0x0000000000000000000000000000000000000000";
let GaugeProxyV2, userSigner, populatedTx, masterChef, Gauge1, Gauge2;

describe("Vote & Distribute : chunk and onlyGov distribution", () => {
  before("Setting up gaugeProxyV2", async () => {
    await resetHardhatNetwork();
    const signer = ethers.provider.getSigner();
    /**
     *  sending gas cost to gov
     * */
    console.log("-- Sending gas cost to governance addr --");
    await signer.sendTransaction({
      to: governanceAddr,
      value: ethers.BigNumber.from("10000000000000000000"), // 1000 ETH
      data: undefined,
    });

    /** unlock governance account */
    await unlockAccount(governanceAddr)

    /** unlock user's account */
    await unlockAccount(userAddr);

    const governanceSigner = ethers.provider.getSigner(governanceAddr);
    userSigner = ethers.provider.getSigner(userAddr);
    const signerAddress = await signer.getAddress()
    
    GaugeProxyV2 = await deployGaugeProxy(governanceSigner);
    Gauge1 = await deployGauge(pickleLP, signerAddress, GaugeProxyV2.address, pickleAddr);
    Gauge2 = await deployGauge(pyveCRVETH, signerAddress, GaugeProxyV2.address, pickleAddr);
    
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

  it("Should successfully test first voting", async () => {

    const gaugeProxyFromUser = GaugeProxyV2.connect(userSigner);

    await expect(
      gaugeProxyFromUser.vote([pickleLP, pyveCRVETH], [6000000], {
        gasLimit: 900000,
      })
    ).to.be.revertedWith("GaugeProxy: token votes count does not match weights count");

    console.log("-- Voting on LP Gauge with 100% weight --");
    await expect(
      gaugeProxyFromUser.vote([pickleLP, pyveCRVETH], [6000000, 4000000], {
        gasLimit: 900000,
      })
    ).to.be.revertedWith("Voting not started yet");

    await expect(gaugeProxyFromUser.reset()).to.be.revertedWith(
      "GaugeProxy: voting not started yet"
    );

    advanceSevenDays();
    console.log(
      "Current Id => ",
      Number(await GaugeProxyV2.getCurrentPeriodId())
    );
    console.log(
      "Distribution Id => ",
      Number(await GaugeProxyV2.distributionId())
    );

    populatedTx = await gaugeProxyFromUser.populateTransaction.vote(
      [pickleLP, pyveCRVETH],
      [6000000, 4000000],
      {
        gasLimit: 900000,
      }
    );
    await userSigner.sendTransaction(populatedTx);
    await GaugeProxyV2.deposit();
    // Adjusts _owner's votes according to latest _owner's DILL balance
    const tokensAry = await GaugeProxyV2.tokens();

    console.log(
      "users pickleLP votes =>",
      await GaugeProxyV2.votes(userAddr, tokensAry[0])
    );
    console.log(
      "users pyveCRVETH votes =>",
      await GaugeProxyV2.votes(userAddr, tokensAry[1])
    );
    //reset users vote
    await gaugeProxyFromUser.reset();

    let pickleLPVotes = await GaugeProxyV2.votes(userAddr, tokensAry[0]);
    let pyveCRVETHVotes = await GaugeProxyV2.votes(userAddr, tokensAry[1]);
    expect(pickleLPVotes).to.equal(0);
    expect(pyveCRVETHVotes).to.equal(0);

    // vote again
    await gaugeProxyFromUser.vote([pickleLP, pyveCRVETH], [6000000, 4000000], {
      gasLimit: 900000,
    });
    pickleLPVotes = await GaugeProxyV2.votes(userAddr, pickleLP);
    pyveCRVETHVotes = await GaugeProxyV2.votes(userAddr, pyveCRVETH);
    expect(Number(pickleLPVotes)).to.greaterThan(0);
    expect(Number(pyveCRVETHVotes)).to.greaterThan(0);

    await hre.network.provider.request({
      method: "evm_mine",
    });
  });

  it("OnlyGov : distribution by non-gov address Should fail", async () => {
    const gaugeProxyFromUser = GaugeProxyV2.connect(userAddr);
    populatedTx = await gaugeProxyFromUser.populateTransaction.distribute(0, 2);
    await expect(userSigner.sendTransaction(populatedTx)).to.be.revertedWith(
      "Operation allowed by only governance"
    );
  });

  it("Distribute(onlyGov) PICKLE to gauges Should fail as voting still in progress", async () => {
    await expect(GaugeProxyV2.distribute(0, 2)).to.be.revertedWith(
      "GaugeProxy: all period distributions complete"
    );
  });

  it("Distribution Should fail when end greater than token[] length is passed ", async () => {
    await advanceSevenDays();
    await expect(GaugeProxyV2.distribute(0, 3)).to.be.revertedWith(
      "GaugeProxy: bad _end"
    );
  });

  it("Successfully Distribute PICKLE(in chunks) to gauges in chunks after advancing 7 days", async () => {
    /**
     * FIRST CHUNK DISTRIBUTION (successful)
     */
    await advanceSevenDays()
    console.log("-- Distributing first chunk (0,1) --");
    await GaugeProxyV2.distribute(0, 1, {
      gasLimit: 900000,
    });

    let pickleGaugeAddr = await GaugeProxyV2.getGauge(pickleLP);
    let yvecrvGaugeAddr = await GaugeProxyV2.getGauge(pyveCRVETH);


    const pickle = await ethers.getContractAt(
      "src/yield-farming/pickle-token.sol:PickleToken",
      pickleAddr
    );

    let pickleRewards = Number(await pickle.balanceOf(pickleGaugeAddr.gaugeAddress));
    console.log("Rewards to Pickle gauge => ", pickleRewards.toString());

    let yvecrvRewards = Number(await pickle.balanceOf(yvecrvGaugeAddr.gaugeAddress));
    console.log("Rewards to pyveCRV gauge => ", yvecrvRewards.toString());
    expect(pickleRewards).to.greaterThan(0);
    expect(yvecrvRewards).to.equal(0);
  });

  it("Should not distribute rewards to gauges when tried to distribute same chunk again", async () => {
    /**
     * FIRST CHUNK DISTRIBUTION (fail)
     */
    console.log("Distributing first chunk(0, 1) again");
    await GaugeProxyV2.distribute(0, 1, {
      gasLimit: 900000,
    });

    let pickleGaugeAddr = await GaugeProxyV2.getGauge(pickleLP);
    let yvecrvGaugeAddr = await GaugeProxyV2.getGauge(pyveCRVETH);

    const pickle = await ethers.getContractAt(
      "src/yield-farming/pickle-token.sol:PickleToken",
      pickleAddr
    );

    let pickleRewards = await pickle.balanceOf(pickleGaugeAddr.gaugeAddress);
    console.log("Rewards to Pickle gauge => ", pickleRewards.toString());

    let yvecrvRewards = await pickle.balanceOf(yvecrvGaugeAddr.gaugeAddress);
    console.log("Rewards to pyveCRV gauge => ", yvecrvRewards.toString());
  });

  it("Should fail when tried to pass wrong start", async () => {
    /**
     * SECOND CHUNK DISTRIBUTION (fail)
     */
    console.log("--Distributing chunk with wrong start--");
    await expect(GaugeProxyV2.distribute(2, 2)).to.be.revertedWith(
      "GaugeProxy: bad _start"
    );
  });

  it("Successfully Distribute PICKLE to gauges in chunks after advancing 7 days", async () => {
    /**
     * SECOND CHUNK DISTRIBUTION (successful)
     */
    console.log("--Distributing second chunk(0,2)--");
    advanceSevenDays();
    await GaugeProxyV2.distribute(1, 2, {
      gasLimit: 900000,
    });
    let pickleGaugeAddr = await GaugeProxyV2.getGauge(pickleLP);
    let yvecrvGaugeAddr = await GaugeProxyV2.getGauge(pyveCRVETH);

    const pickle = await ethers.getContractAt(
      "src/yield-farming/pickle-token.sol:PickleToken",
      pickleAddr
    );

    let pickleRewards = Number(await pickle.balanceOf(pickleGaugeAddr.gaugeAddress));
    console.log("Rewards to Pickle gauge => ", pickleRewards.toString());

    let yvecrvRewards = Number(await pickle.balanceOf(yvecrvGaugeAddr.gaugeAddress));
    console.log("Rewards to pyveCRV gauge => ", yvecrvRewards.toString());
    expect(yvecrvRewards).to.greaterThan(0);
  });
});
