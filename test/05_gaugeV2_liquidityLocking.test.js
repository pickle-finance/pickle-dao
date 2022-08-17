const { advanceNDays, advanceSevenDays } = require("./testHelper");
const hre = require("hardhat");
const { ethers } = require("hardhat");
const { expect } = require("chai");
const chalk = require("chalk");

const governanceAddr = "0x9d074E37d408542FD38be78848e8814AFB38db17";
const userAddr = "0x5c4D8CEE7dE74E31cE69E76276d862180545c307";
const pickleAddr = "0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5";
const pickleHolder = "0x68759973357F5fB3e844802B3E9bB74317358bf7";
const dillHolder = "0x696A27eA67Cec7D3DA9D3559Cb086db0e814FeD3";
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
  userWithNoPickleOrDill;
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
      ethers.utils.formatEther(stake.liquidity),
      "ending timestamp",
      stake.ending_timestamp
    );
  });
  console.log(
    "*******************************************************************************"
  );
};

describe("Liquidity Staking tests", () => {
  before("Setting up gaugeV2", async () => {
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
    await hre.network.provider.request({
      method: "evm_unlockUnknownAccount",
      params: [governanceAddr],
    });

    await hre.network.provider.request({
      method: "evm_unlockUnknownAccount",
      params: [userAddr],
    });

    await hre.network.provider.request({
      method: "evm_unlockUnknownAccount",
      params: [dillHolder],
    });

    await hre.network.provider.request({
      method: "evm_unlockUnknownAccount",
      params: [pickleHolder],
    });

    pickle = await ethers.getContractAt(
      "src/yield-farming/pickle-token.sol:PickleToken",
      pickleAddr
    );

    console.log("-- Deploying Gaugev2 contract --");
    const gaugeV2 = await ethers.getContractFactory(
      "/src/dill/gauge-proxy-v2.sol:GaugeV2",
      pickleHolderSigner
    );
    GaugeV2 = await gaugeV2.deploy(
      pickleAddr,
      governanceAddr,
      pickleHolder,
      ["PICKLE"],
      [pickleAddr]
    );
    await GaugeV2.deployed();
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
      GaugeFromUser.depositAllAndLock(8640, false, { gasLimit: 9000000 })
    ).to.be.revertedWith("Minimum stake time not met");
  });

  it("Should fail to stake when trying to stake for more than maximum time", async () => {
    await pickle.connect(userSigner).approve(thisContractAddr, 0);
    await pickle.connect(userSigner).approve(thisContractAddr, 100000);
    await expect(
      GaugeFromUser.depositAllAndLock(86400 * 366, false, { gasLimit: 9000000 })
    ).to.be.revertedWith("Trying to lock for too long");
  });

  it("Should fail to stake when trying to stake 0 liquidity", async () => {
    await pickle.connect(userSigner).approve(thisContractAddr, 0);
    await pickle.connect(userSigner).approve(thisContractAddr, 100000);
    await expect(
      GaugeFromUser.depositAndLock(0, 86400 * 360, false, { gasLimit: 9000000 })
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
        gasLimit: 9000000,
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

  it("notifyRewardAmount should fail when called by other than distribution or wrong reward array is passed", async () => {
    const bal = await pickle.balanceOf(thisContractAddr);
    await pickle.connect(pickleHolderSigner).approve(thisContractAddr, 0);
    await pickle.connect(pickleHolderSigner).approve(thisContractAddr, bal);
    await expect(
      GaugeFromUser.notifyRewardAmount([bal], { gasLimit: 9000000 })
    ).to.be.revertedWith("Caller is not RewardsDistribution contract");

    await expect(
      GaugeV2.notifyRewardAmount([bal,bal], { gasLimit: 9000000 })
    ).to.be.revertedWith("Rewards count do not match reward token count");
  });

  it("Should get reward amount successfully", async () => {
    const bal = await pickle.balanceOf(thisContractAddr);
    await pickle.connect(pickleHolderSigner).approve(thisContractAddr, 0);
    await pickle.connect(pickleHolderSigner).approve(thisContractAddr, bal);

    await GaugeV2.notifyRewardAmount([bal], {
      gasLimit: 9000000,
    });
    console.log(
      "-- reward rate --",
      Number(ethers.utils.formatEther(await GaugeV2.rewardRates(0)))
    );
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
      gasLimit: 9000000,
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
      GaugeFromUser.withdraw(0, { gasLimit: 9000000 })
    ).to.be.revertedWith("Stake is still locked!");
  });

  it("Should fail to withdraw locked amount if wrong stake index is passed ", async () => {
    await expect(
      GaugeFromUser.withdraw(1, { gasLimit: 9000000 })
    ).to.be.revertedWith("Stake not found");
  });

  it("Should withdraw locked amount successfully", async () => {
    advanceNDays(165);
    await GaugeFromUser.withdraw(0, {
      gasLimit: 9000000,
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
    await gaugeFromDillHolder.deposit(fivePickle, { gasLimit: 9000000 });
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
      gasLimit: 9000000,
    });
    console.log(
      "dillHolder's pickle balance after deposit and lock",
      Number(ethers.utils.formatEther(await pickle.balanceOf(dillHolder)))
    );

    const gaugeFromLuffy = GaugeV2.connect(Luffy);
    // Deposit - Luffy
    await pickle.connect(Luffy).approve(thisContractAddr, 0);
    await pickle.connect(Luffy).approve(thisContractAddr, fivePickle);
    await gaugeFromLuffy.deposit(fivePickle, { gasLimit: 9000000 });
    console.log(
      "Luffy's pickle balance after deposit",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );

    // Deposit and Lock - Luffy
    await pickle.connect(Luffy).approve(thisContractAddr, 0);
    await pickle.connect(Luffy).approve(thisContractAddr, fivePickle);
    await gaugeFromLuffy.depositAndLock(fivePickle, 86400 * 365, false, {
      gasLimit: 9000000,
    });
    console.log(
      "Luffy's pickle balance after deposit and lock",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );

    advanceSevenDays();

    // Deposit - Zoro
    await pickle.connect(Zoro).approve(thisContractAddr, 0);
    await pickle.connect(Zoro).approve(thisContractAddr, fivePickle);
    await GaugeV2.connect(Zoro).deposit(fivePickle, { gasLimit: 9000000 });
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
      { gasLimit: 9000000 }
    );
    console.log(
      "Sanji's pickle balance after deposit and lock",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Sanji.address)))
    );

    // Deposit and Lock - Nami
    await pickle.connect(Nami).approve(thisContractAddr, 0);
    await pickle.connect(Nami).approve(thisContractAddr, fivePickle);
    await GaugeV2.connect(Nami).depositAndLock(fivePickle, 86400 * 365, true, {
      gasLimit: 9000000,
    });
    console.log(
      "Nami's pickle balance after deposit and lock(permanent lock)",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Nami.address)))
    );

    const bal = await pickle.balanceOf(thisContractAddr);
    await pickle.connect(pickleHolderSigner).approve(thisContractAddr, 0);
    await pickle.connect(pickleHolderSigner).approve(thisContractAddr, bal);
    await GaugeV2.notifyRewardAmount([bal], {
      gasLimit: 9000000,
    });
    console.log(
      "-- reward rate --",
      Number(ethers.utils.formatEther(await GaugeV2.rewardRates(0)))
    );
    console.log(
      "--------------------------------------------------------------------------------------"
    );
    advanceNDays(365);

    // exit dillHolder
    await gaugeFromDillHolder.exit({
      gasLimit: 9000000,
    });
    console.log(
      "dillHolder's pickle balance after getting reward and withdrawing deposit (deposit and deposit & lock)",
      Number(ethers.utils.formatEther(await pickle.balanceOf(dillHolder)))
    );

    // exit Luffy
    await gaugeFromLuffy.exit({
      gasLimit: 9000000,
    });
    console.log(
      "Luffy's pickle balance after getting reward and withdrawing deposit (deposit - no dill and deposit & lock)",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Luffy.address)))
    );

    advanceSevenDays();

    // exit Zoro
    await GaugeV2.connect(Zoro).exit({
      gasLimit: 9000000,
    });
    console.log(
      "Zoro's pickle balance after getting reward and withdrawing deposit (deposit)",
      Number(ethers.utils.formatEther(await pickle.balanceOf(Zoro.address)))
    );
    advanceSevenDays();

    // exit Sanji
    await GaugeV2.connect(Sanji).exit({
      gasLimit: 9000000,
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

  it("Should test unlock stakes for account successfully", async () => {
    await pickle.connect(userSigner).approve(thisContractAddr, 0);
    await pickle
      .connect(userSigner)
      .approve(thisContractAddr, ethers.utils.parseEther("0.03"));
    const userBalBeforeDeposit = await pickle.balanceOf(userAddr);
    await GaugeFromUser.depositAndLock(
      ethers.utils.parseEther("0.03"),
      86400 * 365,
      false,
      {
        gasLimit: 9000000,
      }
    );
    const userBalAfterDeposit = await pickle.balanceOf(userAddr);
    expect(userBalBeforeDeposit).not.to.be.eq(userBalAfterDeposit);

    await expect(
      GaugeFromUser.withdraw(1, { gasLimit: 9000000 })
    ).to.be.revertedWith("Stake is still locked!");

    await expect(
      GaugeFromUser.unlockStakeForAccount(userAddr, { gasLimit: 9000000 })
    ).to.be.revertedWith("Operation allowed by only governance");
    await GaugeV2.connect(governanceSigner).unlockStakeForAccount(userAddr);

    const isUnlocked = await GaugeV2.stakesUnlockedForAccount(userAddr);
    expect(isUnlocked).to.be.eq(true);

    await GaugeFromUser.exit({ gasLimit: 9000000 });
  });
  it("Test partial withdrawal", async () => {
    await pickle.connect(dillHolderSigner).approve(thisContractAddr, 0);
    const DillHolderPickleBalance = await pickle
      .connect(dillHolderSigner)
      .balanceOf(dillHolder);
    await pickle
      .connect(dillHolderSigner)
      .approve(thisContractAddr, DillHolderPickleBalance);
    console.log(" -- deposit and lock 5 pickle for 3 days -- ");
    await gaugeFromDillHolder.depositAndLock(fivePickle, 86400 * 3, false, {
      gasLimit: 9000000,
    });
    console.log(" -- deposit and lock 5 pickle for 365 days -- ");
    await gaugeFromDillHolder.depositAndLock(fivePickle, 86400 * 365, false, {
      gasLimit: 9000000,
    });
    console.log(" -- deposit and lock 5 pickle 1 day -- ");
    await gaugeFromDillHolder.depositAndLock(fivePickle, 86400, false, {
      gasLimit: 9000000,
    });
    console.log(" -- deposit all remaining pickle -- ");
    await gaugeFromDillHolder.depositAll({ gasLimit: 9000000 });

    await printStakes(dillHolder);
    advanceSevenDays();

    await expect(
      gaugeFromDillHolder.partialWithdrawal(ethers.utils.parseEther("5000"))
    ).to.be.revertedWith("Withdraw amount exceeds balance");

    // Withdraw 5 pickle (= liquidity in first unlocked stake)
    console.log(" -- Partially withdrawing 5 pickle -- ");
    await gaugeFromDillHolder.partialWithdrawal(fivePickle); // working fine

    await printStakes(dillHolder);

    // Withdraw 2 pickle (< liquidity in first unlocked stake)
    console.log(" -- Partially withdrawing 2 pickle -- ");
    await gaugeFromDillHolder.partialWithdrawal(ethers.utils.parseEther("2")); // working fine

    await printStakes(dillHolder);

    // Withdraw 5 pickle (> liquidity in first unlocked stake)
    console.log(" -- Partially withdrawing 5 pickle -- ");
    await gaugeFromDillHolder.partialWithdrawal(fivePickle);

    await printStakes(dillHolder);
  });
  it("Should test unlock stakes and withdraw all", async () => {
    console.log("-- Permanently staking pickle --");
    gaugeFromDillHolder.depositAllAndLock(86400, true);

    //print stakes
    await printStakes(dillHolder);

    console.log("-- unlocking all stakes --");
    await expect(GaugeV2.unlockStakes()).to.be.revertedWith(
      "Operation allowed by only governance"
    );

    //unlock all stakes
    await GaugeV2.connect(governanceSigner).unlockStakes();

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
    console.log(rewardForDuration);
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
        gasLimit: 9000000,
      })
    ).to.be.revertedWith(
      "Only registered delegates can deposit for their delegator"
    );

    await expect(
      GaugeV2.connect(Luffy).depositForAndLock(
        fivePickle,
        dillHolder,
        86400 * 365,
        false,
        {
          gasLimit: 9000000,
        }
      )
    ).to.be.revertedWith(
      "Only registered delegates can stake for their delegator"
    );

    await GaugeV2.connect(userWithNoPickleOrDill).depositFor(
      fivePickle,
      dillHolder,
      {
        gasLimit: 9000000,
      }
    );
    await GaugeV2.connect(userWithNoPickleOrDill).depositForAndLock(
      fivePickle,
      dillHolder,
      86400 * 365,
      false,
      {
        gasLimit: 9000000,
      }
    );
  });
  it("Should test setMultiplier successfully", async () => {
    await expect(
      GaugeFromUser.setMultipliers(1, { gasLimit: 9000000 })
    ).to.be.revertedWith("Operation allowed by only governance");
    await expect(
      GaugeV2.connect(governanceSigner).setMultipliers(10 ** 14, {
        gasLimit: 9000000,
      })
    ).to.be.revertedWith("Multiplier must be greater than or equal to 1e18");
    const newMultilier = ethers.BigNumber.from("10000000000000000000"); //new BigNumber(10 ** 19).toFixed();
    await GaugeV2.connect(governanceSigner).setMultipliers(newMultilier, {
      gasLimit: 9000000,
    });
    const maxMultiplier = await GaugeV2.lockMaxMultiplier();
    expect(maxMultiplier).to.be.eq(newMultilier);
  });
  it("Should test setMaxRewardsDuration ", async () => {
    await expect(
      GaugeFromUser.setMaxRewardsDuration(86400, { gasLimit: 9000000 })
    ).to.be.revertedWith("Operation allowed by only governance");
    await expect(
      GaugeV2.connect(governanceSigner).setMaxRewardsDuration(8640, {
        gasLimit: 9000000,
      })
    ).to.be.revertedWith("Rewards duration too short");
    advanceSevenDays();
    const newMaxTime = 86400 * 400;
    await GaugeV2.connect(governanceSigner).setMaxRewardsDuration(newMaxTime, {
      gasLimit: 9000000,
    });
    const maxTime = await GaugeV2.lockTimeForMaxMultiplier();
    expect(newMaxTime).to.be.eq(maxTime);
  });
});