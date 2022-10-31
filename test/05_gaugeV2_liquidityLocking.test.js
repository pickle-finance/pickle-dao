const { advanceNDays, advanceSevenDays, resetHardhatNetwork, deployGaugeProxy, unlockAccount } = require("./testHelper");
const hre = require("hardhat");
const { ethers } = require("hardhat");
const { expect } = require("chai");
const chalk = require("chalk");

const governanceAddr = "0x9d074E37d408542FD38be78848e8814AFB38db17";
const userAddr = "0x5c4D8CEE7dE74E31cE69E76276d862180545c307";
const pickleAddr = "0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5";
const pickleHolder = "0x68759973357F5fB3e844802B3E9bB74317358bf7";
const dillHolder = "0xaCfE4511CE883C14c4eA40563F176C3C09b4c47C";
let userSigner,
  GaugeV2,
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
  GaugeProxyV2,
  userWithNoPickleOrDill,
  GaugeFromGovernance;
const fivePickle = ethers.utils.parseEther("5");

const printStakes = async (address) => {
  let stakes = await GaugeV2.lockedStakesOf(address);
  console.log(
    "********************* Locked stakes ********************************************"
  );
  stakes.forEach((stake, index) => {
    console.log(
      "Liquidity in stake ",
      index,
      stake.liquidity,
      "ending timestamp",
      stake.endingTimestamp
    );
  });
  console.log(
    "*******************************************************************************"
  );
};

describe("Liquidity Staking tests", () => {
  before("Setting up gaugeV2", async () => {
    await resetHardhatNetwork();
    const signer = ethers.provider.getSigner();
    pickleHolderSigner = ethers.provider.getSigner(pickleHolder);
    userSigner = ethers.provider.getSigner(userAddr);
    governanceSigner = ethers.provider.getSigner(governanceAddr);
    [Luffy, Zoro, Sanji, Nami, userWithNoPickleOrDill] =
      await ethers.getSigners();

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

    GaugeProxyV2 = await deployGaugeProxy(governanceSigner);
    console.log("GaugeProxyV2 deployed to:", GaugeProxyV2.address);

    console.log("-- Deploying Gaugev2 contract --");
    const gaugeV2 = await ethers.getContractFactory(
      "/src/dill/gauges/GaugeV2.sol:GaugeV2",
      pickleHolderSigner
    );
    GaugeV2 = await gaugeV2.deploy(
      pickleAddr,
      governanceAddr,
      GaugeProxyV2.address
    );
    await GaugeV2.deployed();
    GaugeFromGovernance = GaugeV2.connect(governanceSigner);
    await GaugeFromGovernance.setRewardToken(pickleAddr, governanceAddr);
    thisContractAddr = GaugeV2.address;
    console.log("GaugeV2 deployed to:", thisContractAddr);

    GaugeFromUser = GaugeV2.connect(userSigner);
    const pickleFromHolder = pickle.connect(pickleHolderSigner);

    dillHolderSigner = ethers.provider.getSigner(dillHolder);
    gaugeFromDillHolder = GaugeV2.connect(dillHolderSigner);

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

  it("Should fail to stake when trying to stake for less than minimum time", async () => {
    await expect(
      GaugeFromUser.depositAllAndLock(8640, false, { gasLimit: 900000 })
    ).to.be.revertedWith("Minimum stake time not met");
  });

  it("Should fail to stake when trying to stake for more than maximum time", async () => {
    await pickle.connect(userSigner).approve(thisContractAddr, 0);
    await pickle.connect(userSigner).approve(thisContractAddr, 100000);
    await expect(
      GaugeFromUser.depositAllAndLock(86400 * 366, false, { gasLimit: 900000 })
    ).to.be.revertedWith("Trying to lock for too long");
  });

  it("Should fail to stake when trying to stake 0 liquidity", async () => {
    await pickle.connect(userSigner).approve(thisContractAddr, 0);
    await pickle.connect(userSigner).approve(thisContractAddr, 100000);
    await expect(
      GaugeFromUser.depositAndLock(0, 86400 * 360, false, { gasLimit: 900000 })
    ).to.be.revertedWith("Cannot stake 0");
  });

  it("should stake successfully (first stake)", async () => {
    const pickle = await ethers.getContractAt(
      "src/yield-farming/pickle-token.sol:PickleToken",
      pickleAddr
    );

    console.log(
      "-- User's Pickle balance --",
      Number(ethers.utils.formatEther(await pickle.balanceOf(userAddr)))
    );
    console.log(
      "-- Contracts Pickle balance --",
      Number(ethers.utils.formatEther(await pickle.balanceOf(thisContractAddr)))
    );

    await pickle.connect(userSigner).approve(thisContractAddr, 0);
    await pickle
      .connect(userSigner)
      .approve(thisContractAddr, ethers.utils.parseEther("10"));

    await GaugeFromUser.depositAndLock(
      ethers.utils.parseEther("10"),
      86400 * 365,
      false,
      {
        gasLimit: 900000,
      }
    );

    console.log(
      "-- User's Pickle balance after deposit --",
      Number(ethers.utils.formatEther(await pickle.balanceOf(userAddr)))
    );
    console.log(
      "-- Contracts Pickle balance after deposit --",
      Number(ethers.utils.formatEther(await pickle.balanceOf(thisContractAddr)))
    );
  });

  it("notifyRewardAmount should fail when called by other than distribution", async () => {
    const bal = await pickle.balanceOf(thisContractAddr);
    await pickle.connect(pickleHolderSigner).approve(thisContractAddr, 0);
    await pickle.connect(pickleHolderSigner).approve(thisContractAddr, bal);
    await expect(
      GaugeFromUser.notifyRewardAmount(pickleAddr, bal, { gasLimit: 900000 })
    ).to.be.revertedWith("Caller is not RewardsDistribution contract");
  });

  it("Should get reward amount successfully", async () => {
    const bal = await pickle.balanceOf(thisContractAddr);
    console.log(await pickle.balanceOf(governanceAddr));
    await pickle.connect(governanceSigner).approve(thisContractAddr, 0);
    await pickle.connect(governanceSigner).approve(thisContractAddr, bal);
    await GaugeFromGovernance.notifyRewardAmount(pickleAddr, bal, {
      gasLimit: 900000,
    });
    // console.log(
    //   "-- reward rate --",
    //   Number(ethers.utils.formatEther(await GaugeV2.rewardRates(0)))
    // );
    advanceNDays(200);

    console.log(
      "--------------------------------------------------------------------------------------"
    );
    console.log(
      "-- User's Pickle balance before claiming reward --",
      Number(ethers.utils.formatEther(await pickle.balanceOf(userAddr)))
    );
    console.log(
      "-- Contracts Pickle balance before claiming reward --",
      Number(ethers.utils.formatEther(await pickle.balanceOf(thisContractAddr)))
    );

    console.log(
      "--------------------------------------------------------------------------------------"
    );
    await GaugeFromUser.getReward({
      gasLimit: 900000,
    });

    console.log(
      "-- User's Pickle balance after claiming reward --",
      Number(ethers.utils.formatEther(await pickle.balanceOf(userAddr)))
    );
    console.log(
      "-- Contracts Pickle balance after claiming reward --",
      Number(ethers.utils.formatEther(await pickle.balanceOf(thisContractAddr)))
    );
    console.log(
      "--------------------------------------------------------------------------------------"
    );
  });

  it("Should fail to withdraw locked amount if stake is still locked", async () => {
    await expect(
      GaugeFromUser.withdrawUnlockedStake()
    ).to.be.revertedWith("Cannot withdraw more than non-staked amount");
  });

  it("Should withdraw locked amount successfully", async () => {
    advanceNDays(165);
    await GaugeFromUser.withdrawUnlockedStake({
      gasLimit: 900000,
    });
    console.log(
      "-- User's Pickle balance after withdraw --",
      Number(ethers.utils.formatEther(await pickle.balanceOf(userAddr)))
    );
    console.log(
      "-- Contracts Pickle balance after withdraw --",
      Number(ethers.utils.formatEther(await pickle.balanceOf(thisContractAddr)))
    );
  });

  it("Should test unlock stakes for account successfully", async () => {
    await pickle.connect(userSigner).approve(thisContractAddr, 0);
    await pickle
      .connect(userSigner)
      .approve(thisContractAddr, ethers.utils.parseEther("0.03"));

    const userBalBeforeDeposit = await pickle.balanceOf(userAddr);
    (userBalBeforeDeposit);
    await GaugeFromUser.depositAndLock(
      ethers.utils.parseEther("0.03"),
      86400 * 365,
      false,
      {
        gasLimit: 5999999,
      }
    );

    const userBalAfterDeposit = await pickle.balanceOf(userAddr);
    expect(userBalBeforeDeposit).not.to.be.eq(userBalAfterDeposit);

    await expect(
      GaugeFromUser.withdrawNonStaked(1, { gasLimit: 5999999 })
    ).to.be.revertedWith("Cannot withdraw more than your non-staked balance");

    await expect(
      GaugeFromUser.unlockStakeForAccount(userAddr, { gasLimit: 5999999 })
    ).to.be.revertedWith("Operation allowed by only governance");
    await GaugeFromGovernance.unlockStakeForAccount(userAddr);

    const isUnlocked = await GaugeV2.stakesUnlockedForAccount(userAddr);
    ("isUnlocked", isUnlocked);
    expect(isUnlocked).to.be.eq(true);

    const bal = await pickle.balanceOf(thisContractAddr);
    await pickle.connect(governanceSigner).approve(thisContractAddr, 0);
    await pickle.connect(governanceSigner).approve(thisContractAddr, bal);
    await GaugeFromGovernance.notifyRewardAmount(pickleAddr, bal, {
      gasLimit: 5999999,
    });
    await GaugeFromUser.exit({ gasLimit: 6000000 });

  });

  it("Should test deposit, deposit and lock, permanent lock and get reward successfully for dill holder and non-holder users", async () => {
    console.log(
      "==================================================================================================="
    );
    console.log(
      "dillHolder's pickle balance ",
      Number(ethers.utils.formatEther(await pickle.balanceOf(dillHolder)))
    );
    console.log(
      "Luffy's pickle balance ",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );
    console.log(
      "Zoro's pickle balance ",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Zoro.address)))
    );
    console.log(
      "Sanji's pickle balance ",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Sanji.address)))
    );
    console.log(
      "Nami's pickle balance ",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Nami.address)))
    );
    console.log(
      "==================================================================================================="
    );

    // Deposit - dillHolder
    await pickle.connect(dillHolderSigner).approve(thisContractAddr, 0);
    await pickle
      .connect(dillHolderSigner)
      .approve(thisContractAddr, fivePickle);
    await gaugeFromDillHolder.deposit(fivePickle, { gasLimit: 900000 });
    console.log(
      "dillHolder's pickle balance after deposit",
      Number(ethers.utils.formatEther(await pickle.balanceOf(dillHolder)))
    );

    // Deposit and Lock - dillHolder
    await pickle.connect(dillHolderSigner).approve(thisContractAddr, 0);
    await pickle
      .connect(dillHolderSigner)
      .approve(thisContractAddr, fivePickle);
    await gaugeFromDillHolder.depositAndLock(fivePickle, 86400 * 365, false, {
      gasLimit: 900000,
    });
    console.log(
      "dillHolder's pickle balance after deposit and lock",
      Number(ethers.utils.formatEther(await pickle.balanceOf(dillHolder)))
    );

    const gaugeFromLuffy = GaugeV2.connect(Luffy);
    // Deposit - Luffy
    await pickle.connect(Luffy).approve(thisContractAddr, 0);
    await pickle.connect(Luffy).approve(thisContractAddr, fivePickle);
    await gaugeFromLuffy.deposit(fivePickle, { gasLimit: 900000 });
    console.log(
      "Luffy's pickle balance after deposit",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );

    // Deposit and Lock - Luffy
    await pickle.connect(Luffy).approve(thisContractAddr, 0);
    await pickle.connect(Luffy).approve(thisContractAddr, fivePickle);
    await gaugeFromLuffy.depositAndLock(fivePickle, 86400 * 365, false, {
      gasLimit: 900000,
    });
    console.log(
      "Luffy's pickle balance after deposit and lock",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );

    advanceSevenDays();

    // Deposit - Zoro
    await pickle.connect(Zoro).approve(thisContractAddr, 0);
    await pickle.connect(Zoro).approve(thisContractAddr, fivePickle);
    await GaugeV2.connect(Zoro).deposit(fivePickle, { gasLimit: 900000 });
    console.log(
      "Zoro's pickle balance after deposit",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Zoro.address)))
    );

    advanceSevenDays();

    // Deposit and Lock - Sanji
    await pickle.connect(Sanji).approve(thisContractAddr, 0);
    await pickle.connect(Sanji).approve(thisContractAddr, fivePickle);
    await GaugeV2.connect(Sanji).depositAndLock(
      fivePickle,
      86400 * 365,
      false,
      { gasLimit: 900000 }
    );
    console.log(
      "Sanji's pickle balance after deposit and lock",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Sanji.address)))
    );

    // Deposit and Lock - Nami
    await pickle.connect(Nami).approve(thisContractAddr, 0);
    await pickle.connect(Nami).approve(thisContractAddr, fivePickle);
    await GaugeV2.connect(Nami).depositAndLock(fivePickle, 86400 * 365, true, {
      gasLimit: 900000,
    });
    console.log(
      "Nami's pickle balance after deposit and lock(permanent lock)",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Nami.address)))
    );

    const bal = await pickle.balanceOf(thisContractAddr);
    await pickle.connect(governanceSigner).approve(thisContractAddr, 0);
    await pickle.connect(governanceSigner).approve(thisContractAddr, bal);
    await GaugeFromGovernance.notifyRewardAmount(pickleAddr, bal, {
      gasLimit: 900000,
    });
    // console.log(
    //   "-- reward rate --",
    //   Number(ethers.utils.formatEther(await GaugeV2.rewardRates(0)))
    // );
    console.log(
      "--------------------------------------------------------------------------------------"
    );
    advanceNDays(365);
    // exit dillHolder
    await gaugeFromDillHolder.exit({
      gasLimit: 5999999,
    });
    console.log(
      "dillHolder's pickle balance after getting reward and withdrawing deposit (deposit and deposit & lock)",
      Number(ethers.utils.formatEther(await pickle.balanceOf(dillHolder)))
    );
    // exit Luffy
    await gaugeFromLuffy.exit({
      gasLimit: 5999999,
    });
    console.log(
      "Luffy's pickle balance after getting reward and withdrawing deposit (deposit - no dill and deposit & lock)",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );

    advanceSevenDays();

    // exit Zoro
    await GaugeV2.connect(Zoro).exit({
      gasLimit: 5999999,
    });
    console.log(
      "Zoro's pickle balance after getting reward and withdrawing deposit (deposit)",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Zoro.address)))
    );
    advanceSevenDays();

    // exit Sanji
    await GaugeV2.connect(Sanji).exit({
      gasLimit: 5999999,
    });
    console.log(
      "Sanji's pickle balance after getting reward and withdrawing deposit (deposit & lock)",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Sanji.address)))
    );

    await printStakes(Nami.address);
    //getReward Nami (permanent lock)
    await GaugeV2.connect(Nami).getReward();
    console.log(
      "Nami's pickle balance after getting reward (2.5x because stakes are permanently locked)",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Nami.address)))
    );
    console.log(
      "--------------------------------------------------------------------------------------"
    );
  });

  it("Should test unlock stakes and withdraw all", async () => {
    await pickle.connect(dillHolderSigner).approve(thisContractAddr, 0);
    let DillHolderPickleBalance = await pickle
      .connect(dillHolderSigner)
      .balanceOf(dillHolder);
    await pickle
      .connect(dillHolderSigner)
      .approve(thisContractAddr, DillHolderPickleBalance);

    console.log("-- Permanently staking pickle --");
    gaugeFromDillHolder.depositAllAndLock(86400, true);
    console.log(await pickle.balanceOf(thisContractAddr));
    DillHolderPickleBalance = await pickle
      .connect(dillHolderSigner)
      .balanceOf(dillHolder);
    console.log("AFTER", DillHolderPickleBalance);

    //print stakes
    await printStakes(dillHolder);

    console.log("-- unlocking all stakes --");
    await expect(GaugeV2.unlockStakes()).to.be.revertedWith(
      "Operation allowed by only governance"
    );

    //unlock all stakes
    await GaugeFromGovernance.unlockStakes();

    // withdraw all
    console.log(" -- Withdrawing all unlocked stakes of dillHolder -- ");
    await gaugeFromDillHolder.withdrawAll();
    //print stakes
    await printStakes(dillHolder);
  });
  it("Should check max lockMultiplier and rewardForDuration", async () => {
    const multiplierFor1year = await GaugeV2.lockMultiplier(86400 * 365);
    const multiplierFor2year = await GaugeV2.lockMultiplier(86400 * 365 * 2);
    expect(multiplierFor1year).to.equal(multiplierFor2year);

    const rewardForDuration = await GaugeV2.getRewardForDuration();
    console.log(rewardForDuration, multiplierFor1year, multiplierFor2year);
  });
  it("Should set and test staking delegation successfully", async () => {
    // console.log("Staking delegate => ", await GaugeV2.stakingDelegates(dillHolder,dillHolder));
    // set delegate
    await expect(
      gaugeFromDillHolder.setStakingDelegate(dillHolder)
    ).to.be.revertedWith("Cannot delegate to self");

    await gaugeFromDillHolder.setStakingDelegate(
      userWithNoPickleOrDill.address
    );
    await expect(
      gaugeFromDillHolder.setStakingDelegate(userWithNoPickleOrDill.address)
    ).to.be.revertedWith("Already a staking delegate for user!");

    const DillHolderPickleBalance = await pickle
      .connect(dillHolderSigner)
      .balanceOf(dillHolder);
    await pickle
      .connect(dillHolderSigner)
      .approve(thisContractAddr, DillHolderPickleBalance);

    await expect(
      GaugeV2.connect(Luffy).depositFor(fivePickle, dillHolder, {
        gasLimit: 900000,
      })
    ).to.be.revertedWith(
      "Only registerd delegates can deposit for their deligator"
    );

    await expect(
      GaugeV2.connect(Luffy).depositForAndLock(
        fivePickle,
        dillHolder,
        86400 * 365,
        false,
        {
          gasLimit: 900000,
        }
      )
    ).to.be.revertedWith(
      "Only registerd delegates can stake for their deligator"
    );

    await GaugeV2.connect(userWithNoPickleOrDill).depositFor(
      fivePickle,
      dillHolder,
      {
        gasLimit: 900000,
      }
    );
    await GaugeV2.connect(userWithNoPickleOrDill).depositForAndLock(
      fivePickle,
      dillHolder,
      86400 * 365,
      false,
      {
        gasLimit: 900000,
      }
    );
  });
});
