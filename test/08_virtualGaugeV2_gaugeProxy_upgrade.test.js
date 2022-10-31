const { advanceNDays, advanceSevenDays, resetHardhatNetwork, deployGaugeProxy, unlockAccount } = require("./testHelper");
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const { expect } = require("chai");
const chalk = require("chalk");

const governanceAddr = "0x9d074E37d408542FD38be78848e8814AFB38db17";
const userAddr = "0x5c4D8CEE7dE74E31cE69E76276d862180545c307";
const pickleLP = "0xdc98556Ce24f007A5eF6dC1CE96322d65832A819";
const pickleAddr = "0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5";
const pyveCRVETH = "0x5eff6d166d66bacbc1bf52e2c54dd391ae6b1f48";
const pickleHolder = "0x68759973357F5fB3e844802B3E9bB74317358bf7";
const dillHolder = "0x696A27eA67Cec7D3DA9D3559Cb086db0e814FeD3";
const masterChefAddr = "0xbD17B1ce622d73bD438b9E658acA5996dc394b0d";
const zeroAddr = "0x0000000000000000000000000000000000000000";

let userSigner,
  Jar,
  VirtualGaugeV2,
  GaugeProxyV2,
  thisContractAddr,
  GaugeFromUser,
  pickle,
  pickleHolderSigner,
  governanceSigner,
  dillHolderSigner,
  gaugeFromDillHolder,
  Luffy,
  Zoro,
  Sanji,
  Nami,
  GaugeFromGovernance,
  userWithNoPickleOrDill;
const fivePickle = ethers.utils.parseEther("5");

describe("Liquidity Staking tests", () => {
  before("Setting up gaugeV2", async () => {
    resetHardhatNetwork();
    const signer = ethers.provider.getSigner();
    pickleHolderSigner = ethers.provider.getSigner(pickleHolder);
    userSigner = ethers.provider.getSigner(userAddr);
    governanceSigner = ethers.provider.getSigner(governanceAddr);
    [Luffy, Zoro, Sanji, Nami, userWithNoPickleOrDill] =
      await ethers.getSigners();

    console.log("-- Sending gas cost to governance addr --");
    await Nami.sendTransaction({
      to: governanceAddr,
      value: ethers.BigNumber.from("10000000000000000000"),
      data: undefined,
    });

    console.log("-- Sending gas cost to dillHolder addr --");
    await Nami.sendTransaction({
      to: dillHolder,
      value: ethers.BigNumber.from("10000000000000000000"),
      data: undefined,
    });

    console.log("------------------------ sent ------------------------");

    /** unlock accounts */
    await unlockAccount(governanceAddr);
    await unlockAccount(userAddr);
    await unlockAccount(dillHolder);
    await unlockAccount(pickleHolder);

    pickle = await ethers.getContractAt(
      "src/yield-farming/pickle-token.sol:PickleToken",
      pickleAddr
    );

    console.log("-- Deploying jar contract --");
    const jar = await ethers.getContractFactory(
      "/src/dill/JarTemp.sol:JarTemp",
      pickleHolderSigner
    );
    Jar = await jar.deploy();
    await Jar.deployed();
    console.log("Jar deployed at", Jar.address);

    console.log("Deploying MasterChef...");
    GaugeProxyV2 = await deployGaugeProxy(governanceSigner);
    console.log("GaugeProxyV2 deployed to:", GaugeProxyV2.address);

    const mDILLAddr = await GaugeProxyV2.TOKEN();
    console.log("-- Adding mDILL to MasterChef --");

    let populatedTx = await masterChef.populateTransaction.add(
      5000000,
      mDILLAddr,
      false
    );
    await governanceSigner.sendTransaction(populatedTx);

    console.log("-- Deploying VirtualGaugeV2 contract --");
    const virtualGaugeV2 = await ethers.getContractFactory(
      "/src/dill/gauges/VirtualGaugeV2.sol:VirtualGaugeV2",
      pickleHolderSigner
    );

    VirtualGaugeV2 = await virtualGaugeV2.deploy(
      Jar.address,
      governanceAddr,
      GaugeProxyV2.address
    );

    await VirtualGaugeV2.deployed();
    thisContractAddr = VirtualGaugeV2.address;
    await VirtualGaugeV2.connect(governanceSigner).setRewardToken(pickleAddr, GaugeProxyV2.address);
    console.log("VirtualGaugeV2 deployed to:", thisContractAddr);

    GaugeFromGovernance = VirtualGaugeV2.connect(governanceSigner);
    GaugeFromUser = VirtualGaugeV2.connect(userSigner);
    const pickleFromHolder = pickle.connect(pickleHolderSigner);

    dillHolderSigner = ethers.provider.getSigner(dillHolder);
    gaugeFromDillHolder = VirtualGaugeV2.connect(dillHolderSigner);

    console.log(
      "------------------------ Depositing pickle ------------------------"
    );
    await pickleFromHolder.transfer(dillHolder, ethers.utils.parseEther("100"));
    await pickleFromHolder.transfer(userAddr, ethers.utils.parseEther("10"));
    await pickleFromHolder.transfer(
      Luffy.address,
      ethers.utils.parseEther("10")
    );
    await pickleFromHolder.transfer(
      Zoro.address,
      ethers.utils.parseEther("10")
    );
    await pickleFromHolder.transfer(
      Sanji.address,
      ethers.utils.parseEther("10")
    );
    await pickleFromHolder.transfer(
      Nami.address,
      ethers.utils.parseEther("10")
    );
    console.log(
      "------------------------       Done        ------------------------"
    );
  });
  // await hre.network.provider.send("hardhat_reset");
  it.only("Should successfully test virtual Gauge and gaugeProxyV2 together", async () => {
    //deploy gaugeproxy
    userSigner = ethers.provider.getSigner(userAddr);
    const masterChef = await ethers.getContractAt(
      "src/yield-farming/masterchef.sol:MasterChef",
      masterChefAddr,
      governanceSigner
    );
    masterChef.connect(governanceSigner);

    await expect(
      GaugeProxyV2.connect(userSigner).addVirtualGauge(
        pickleAddr,
        0,
        thisContractAddr
      )
    ).to.be.revertedWith("Operation allowed by only governance");

    await expect(
      GaugeProxyV2.connect(governanceSigner).addVirtualGauge(
        pickleAddr,
        0,
        zeroAddr
      )
    ).to.be.revertedWith("GaugeProxy: invalid Gauge Address");

    await GaugeProxyV2.connect(governanceSigner).addVirtualGauge(
      pickleAddr,
      0,
      thisContractAddr
    )

    console.log("-- Adding PICKLE LP Gauge --");
    await GaugeProxyV2.addGauge(pickleLP, 0, thisContractAddr);

    console.log("-- Adding pyveCRVETH Gauge --");
    await GaugeProxyV2.addGauge(pyveCRVETH, 0, thisContractAddr);


    // vote
    console.log("-- VOTING --");
    advanceSevenDays();
    populatedTx = await GaugeProxyV2.connect(
      userSigner
    ).populateTransaction.vote([pickleLP, pyveCRVETH], [6000000, 4000000], {
      gasLimit: 5999999,
    });
    await userSigner.sendTransaction(populatedTx);

  });
  it.only("Should upgrade gaugeProxy successfully", async () => {
    advanceSevenDays();
    const gaugeProxyV2 = await ethers.getContractFactory(
      "/src/dill/gauge-proxies/gauge-proxy-v2.sol:GaugeProxyV2",
      governanceSigner
    );
    console.log("Upgrading GaugeProxy...");
    const upgradeGaugeProxy = await upgrades.upgradeProxy(
      GaugeProxyV2.address, // address of proxy deployed
      gaugeProxyV2
    );
    console.log("gaugeProxy upgraded");

    console.log("check =>", await upgradeGaugeProxy.length());
    console.log("HHH", await VirtualGaugeV2.rewardTokenDetails(pickleAddr));
    console.log("-- Distributing --");
    await GaugeProxyV2.connect(governanceSigner).distribute(0, 2, {
      gasLimit: 5999999,
    });

    let pickleGaugeAddr = await GaugeProxyV2.getGauge(pickleLP);
    let yvecrvGaugeAddr = await GaugeProxyV2.getGauge(pyveCRVETH);
    let pickleRewards = Number(await pickle.balanceOf(pickleGaugeAddr.gaugeAddress));
    console.log("Rewards to Pickle gauge => ", pickleRewards.toString());
    let yvecrvRewards = Number(await pickle.balanceOf(yvecrvGaugeAddr.gaugeAddress));
    console.log("Rewards to pyveCRV gauge => ", yvecrvRewards.toString());
  });
});
