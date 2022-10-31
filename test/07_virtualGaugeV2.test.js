const { advanceSevenDays, advanceNDays, resetHardhatNetwork, deployGaugeProxy, unlockAccount } = require("./testHelper");
const hre = require("hardhat");
const { ethers } = require("hardhat");
const { expect } = require("chai");

const governanceAddr = "0x9d074E37d408542FD38be78848e8814AFB38db17";
const userAddr = "0x5c4D8CEE7dE74E31cE69E76276d862180545c307";
const pickleLP = "0xdc98556Ce24f007A5eF6dC1CE96322d65832A819";
const pickleAddr = "0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5";

const pickleHolder = "0x68759973357F5fB3e844802B3E9bB74317358bf7";
const dillHolder = "0x696A27eA67Cec7D3DA9D3559Cb086db0e814FeD3";

const zeroAddr = "0x0000000000000000000000000000000000000000";

let userSigner,
  Jar,
  VirtualGaugeV2,
  thisContractAddr,
  pickle,
  pickleHolderSigner,
  governanceSigner,
  dillHolderSigner,
  Luffy,
  Zoro,
  Sanji,
  Nami,
  GaugeFromGovernance,
  GaugeProxyV2;
const fivePickle = ethers.utils.parseEther("5");

describe("Liquidity Staking tests", () => {
  before("Setting up gaugeV2", async () => {
    await resetHardhatNetwork();
    const signer = ethers.provider.getSigner();
    pickleHolderSigner = ethers.provider.getSigner(pickleHolder);
    userSigner = ethers.provider.getSigner(userAddr);
    governanceSigner = ethers.provider.getSigner(governanceAddr);
    [Luffy, Zoro, Sanji, Nami] = await ethers.getSigners();

    console.log("-- Sending gas cost to governance addr --");
    await signer.sendTransaction({
      to: governanceAddr,
      value: ethers.BigNumber.from("10000000000000000000"),
      data: undefined,
    });

    console.log("-- Sending gas cost to dillHolder addr --");
    await signer.sendTransaction({
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

    GaugeProxyV2 = await deployGaugeProxy(governanceSigner);

    console.log("GaugeProxyV2 deployed to:", GaugeProxyV2.address);

    console.log("-- Deploying VirtualGaugeV2 contract --");
    const virtualGaugeV2 = await ethers.getContractFactory(
      "/src/dill/gauges/VirtualGaugeV2.sol:VirtualGaugeV2",
      pickleHolderSigner
    );
    await expect(
      virtualGaugeV2.deploy(
        zeroAddr,
        governanceAddr,
        GaugeProxyV2.address
      )
    ).to.be.revertedWith("Cannot set token to zero address");
    VirtualGaugeV2 = await virtualGaugeV2.deploy(
      Jar.address,
      governanceAddr,
      GaugeProxyV2.address
    );

    await VirtualGaugeV2.deployed();
    thisContractAddr = VirtualGaugeV2.address;
    console.log("VirtualGaugeV2 deployed to:", thisContractAddr);
    GaugeFromGovernance = VirtualGaugeV2.connect(governanceSigner);

    const pickleFromHolder = pickle.connect(pickleHolderSigner);

    dillHolderSigner = ethers.provider.getSigner(dillHolder);

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
  it("Should test staking successFully", async () => {
    // approve => jar by => Luffy
    console.log(
      "Luffy's pickle balance => ",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );
    // await pickle.connect(Luffy).approve(Jar.address, fivePickle);

    console.log(
      "Pickle Balance of Luffy before depositing =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );

    //Approve pickle for deposit
    await pickle.connect(Luffy).approve(Jar.address, fivePickle);

    await expect(
      Jar.depositForByJar(fivePickle, Luffy.address)
    ).to.be.revertedWith("set jar first");

    // Set Jar
    await Jar.setVirtualGauge(VirtualGaugeV2.address);
    const jarAd = await Jar.getVirtualGauge();
    console.log("Virtual Gauge =>", jarAd);

    // Deposit pickle
    console.log("-- Depositing 5 pickle for Luffy --");
    await Jar.depositForByJar(fivePickle, Luffy.address);
    console.log(
      "Jar Balance of Luffy",
      Number(ethers.utils.formatEther(await Jar.getBalanceOf(Luffy.address)))
    );
    console.log(
      "Pickle Balance of Luffy =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );
    console.log(
      "Pickle Balance of Jar =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Jar.address)))
    );

    //Approve pickle for deposit and lock
    await pickle.connect(Luffy).approve(Jar.address, fivePickle);

    // Deposit and lock
    console.log("-- Deposit and lock 5 pickle for Luffy --");

    await expect(
      Jar.depositForAndLockByJar(0, Luffy.address, 86400 * 30, false, {
        gasLimit: 5999999,
      })
    ).to.be.revertedWith("Cannot deposit 0");

    await Jar.depositForAndLockByJar(
      fivePickle,
      Luffy.address,
      86400 * 30,
      false,
      {
        gasLimit: 5999999,
      }
    );
    //Approve pickle for deposit and lock
    await pickle.connect(Sanji).approve(Jar.address, fivePickle);

    // Deposit and lock
    console.log("-- Deposit and lock 5 pickle for Sanji --");
    await Jar.depositForAndLockByJar(
      fivePickle,
      Sanji.address,
      86400 * 300,
      false,
      {
        gasLimit: 5999999,
      }
    );

    //Approve pickle for deposit and lock
    await pickle.connect(Zoro).approve(Jar.address, fivePickle);

    // Deposit and lock
    console.log("-- Deposit and lock 5 pickle for Sanji --");
    await Jar.depositForAndLockByJar(
      fivePickle,
      Zoro.address,
      86400 * 300,
      false,
      {
        gasLimit: 5999999,
      }
    );
    console.log(
      "Jar Balance of Luffy",
      Number(ethers.utils.formatEther(await Jar.getBalanceOf(Luffy.address)))
    );
    console.log(
      "Pickle Balance of Luffy =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );
    console.log(
      "Pickle Balance of Jar =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Jar.address)))
    );

    advanceSevenDays();

    // withdraw
    console.log("-- Withdrawing Luffy's stake");
    await expect(Jar.withdrawNonStakedByJar(Luffy.address, ethers.utils.parseEther("10"))).to.be.revertedWith(
      "Cannot withdraw more than your non-staked balance"
    );

    await Jar.withdrawNonStakedByJar(Luffy.address, ethers.utils.parseEther("5"));

    console.log(
      "Jar Balance of Luffy",
      Number(ethers.utils.formatEther(await Jar.getBalanceOf(Luffy.address)))
    );
    console.log(
      "Pickle Balance of Luffy =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );
    console.log(
      "Pickle Balance of Jar =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Jar.address))))


    // notify reward
    const bal = await pickle.balanceOf(Jar.address);
    await pickle.connect(governanceSigner).approve(thisContractAddr, 0);
    await pickle.connect(governanceSigner).approve(thisContractAddr, bal);
    await expect(
      VirtualGaugeV2.connect(userSigner).notifyRewardAmount(pickleAddr, bal, {
        gasLimit: 5999999,
      })
    ).to.be.revertedWith("Caller is not RewardsDistribution contract");

    console.log("--Executing NotifyReward --");
    GaugeFromGovernance.notifyRewardAmount(pickleAddr, bal, {
      gasLimit: 5999999,
    })

    console.log("-- RE-Executing NotifyReward --");
    await GaugeFromGovernance.setRewardToken(pickleAddr, governanceAddr);
    const bal2 = await pickle.balanceOf(Jar.address);
    await pickle.connect(governanceSigner).approve(thisContractAddr, 0);
    await pickle.connect(governanceSigner).approve(thisContractAddr, bal2);
    await GaugeFromGovernance.notifyRewardAmount(pickleAddr, bal2, {
      gasLimit: 5999999,
    });

    //get Reward
    console.log(
      "Pickle Balance of Luffy =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );
    console.log("Total Supply =>", await VirtualGaugeV2.totalSupply());
    console.log("--Executing get reward --");
    await Jar.getRewardByJar(Luffy.address, {
      gasLimit: 5999999,
    });
    console.log(
      "Pickle Balance of Luffy =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );

    console.log("-- Unlocking Stakes for Luffy --");
    // console.log()
    await VirtualGaugeV2.connect(governanceSigner).unlockStakeForAccount(
      Luffy.address
    );

    console.log(
      "Pickle Balance of Luffy =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );
    console.log("-- Withdrawing --");
    await Jar.withdrawAllByJar(Luffy.address);
    console.log(
      "Pickle Balance of Luffy =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );


    console.log(
      "Pickle Balance of Luffy =>",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Sanji.address)))
    );

    // Test multipliers for 1 year and 300 year should be equal
    const multiplierForOneYear = await VirtualGaugeV2.lockMultiplier(
      86400 * 365
    );
    const multiplierForTwentyYear = await VirtualGaugeV2.lockMultiplier(
      86400 * 365 * 20
    );
    expect(multiplierForOneYear).to.eq(multiplierForTwentyYear);

    console.log(" -- Emergency unlock all stakes -- ");
    await VirtualGaugeV2.connect(governanceSigner).unlockStakes();

    console.log("-- Exiting Zoro -- ");
    await Jar.exitByJar(Zoro.address);

    console.log("--Locking emergency unlock for all stakes -- ");
    await VirtualGaugeV2.connect(governanceSigner).unlockStakes();

    //maxMultiplier and duration
    const multiplierFor1year = await VirtualGaugeV2.lockMultiplier(86400 * 365);
    const multiplierFor2year = await VirtualGaugeV2.lockMultiplier(
      86400 * 365 * 2
    );
    expect(multiplierFor1year).to.equal(multiplierFor2year);

    const rewardForDuration = await VirtualGaugeV2.getRewardForDuration();
    console.log("rewardForDuration =>", rewardForDuration);
  });
  it("Test partial withdrawal", async () => {
    await pickle.connect(dillHolderSigner).approve(Jar.address, 0);

    const DillHolderPickleBalance = await pickle
      .connect(dillHolderSigner)
      .balanceOf(dillHolder);
    await pickle
      .connect(dillHolderSigner)
      .approve(Jar.address, DillHolderPickleBalance);
    await expect(
      Jar.depositForAndLockByJar(fivePickle, dillHolder, 86, false, {
        gasLimit: 5999999,
      })
    ).to.be.revertedWith("Minimum stake time not met");

    await expect(
      Jar.depositForAndLockByJar(fivePickle, dillHolder, 86400 * 401, false, {
        gasLimit: 5999999,
      })
    ).to.be.revertedWith("Trying to lock for too long");

    console.log(" -- deposit and lock 5 pickle for 3 days -- ");
    await Jar.depositForAndLockByJar(fivePickle, dillHolder, 86400 * 3, false, {
      gasLimit: 5999999,
    });

    await expect(Jar.withdrawUnlockedStakedByJar(dillHolder)).to.be.revertedWith(
      "Cannot withdraw more than non-staked amount"
    );

    console.log(" -- deposit and lock 5 pickle 1 day -- ");
    await Jar.depositForAndLockByJar(fivePickle, dillHolder, 86400, false, {
      gasLimit: 5999999,
    });
    await advanceNDays(1);

    await expect(Jar.withdrawUnlockedStakedByJar(dillHolder)).to.be.revertedWith(
      "Cannot withdraw more than non-staked amount"
    );

    advanceSevenDays();
    await Jar.withdrawUnlockedStakedByJar(dillHolder)
  });
  // await hre.network.provider.send("hardhat_reset");
});
