// ftm test => rinkeby
const { ethers } = require("hardhat");

const anyCallClientMainChain = "0x9251F943286E2e1Ac8D3a09a9E5bD0E7DE766ba0";
const tempPickleMainChain = "0x10359ea43A7c06A0ccE9F3F1F216961081Cd7Bd6";
const rootGaugeMainChain = "0x10bB5EA0bc1DFebc3a5910940c0047Bcf4FC0E8f";


const main = async () => {
  const [deployer] = await ethers.getSigners();
  const bal = await ethers.provider.getBalance(deployer.address);

  const anyCallClient = await ethers.getContractAt(
    "/src/dill/anySwap/AnyCallClient.sol:AnyswapTokenAnycallClient",
    anyCallClientMainChain
  );
  console.log("setting distributor");
  await anyCallClient.setDistributor(rootGaugeMainChain);
  console.log("Deployer address => ", deployer.address);
  console.log("deployer balance =>", Number(ethers.utils.formatEther(bal)));

  // await deployer.sendTransaction({
  //   to: rootGaugeMainChain,
  //   value: ethers.utils.parseEther("1"), // 1000 ETH
  //   data: undefined,
  // });

  const bal1 = await ethers.provider.getBalance(rootGaugeMainChain);
  console.log("rootGauge balance =>", bal1);

  const anyRootGauge = await ethers.getContractAt(
    "/src/dill/gauges/sidechains/AnyswapRootGauge.sol:AnyswapRootGauge",
    rootGaugeMainChain
  );
  // console.log("setting reward token");
  // await anyRootGauge.setRewardToken(tempPickleSideChain, deployer.address);

  const TempPickleMain = await ethers.getContractAt(
    "/src/yield-farming/pickle-token.sol:PickleToken",
    tempPickleMainChain
  );
  console.log("approving pickle ");
  const tx0 = await TempPickleMain.approve(rootGaugeMainChain, ethers.utils.parseEther("1000"));
  await tx0.wait();
  // await TempPickleMain.approve("0x9251F943286E2e1Ac8D3a09a9E5bD0E7DE766ba0", ethers.utils.parseEther("100"));
  console.log(
    "pickle allowance of rootGauge =>",
    Number(
      ethers.utils.formatEther(
        await TempPickleMain.allowance(deployer.address, rootGaugeMainChain)
      )
    )
  );

  console.log(
    "deployer TempPickleMain Balance => ",
    Number(
      ethers.utils.formatEther(await TempPickleMain.balanceOf(deployer.address))
    )
  );
  console.log(
    "anyRootGauge TempPickleMain Balance => ",
    Number(
      ethers.utils.formatEther(await TempPickleMain.balanceOf(rootGaugeMainChain))
    )
  );
  console.log("executing notifyReward");
  const foo = await anyRootGauge.notifyRewardAmount(
    tempPickleMainChain,
    ethers.utils.parseEther("100"),
    [20000, 80000],
    1,
    {
      value: ethers.utils.parseEther("0.005"),
      gasLimit: 900000,
    }
  );
  const f = await foo.wait();
  console.log(f);
  console.log(
    "deployer TempPickleMain Balance => ",
    Number(
      ethers.utils.formatEther(await TempPickleMain.balanceOf(deployer.address))
    )
  );
  console.log(
    "anyRootGauge TempPickleMain Balance => ",
    Number(
      ethers.utils.formatEther(await TempPickleMain.balanceOf(rootGaugeMainChain))
    )
  );
 
  // fetch(
  //   "https://api-rinkeby.etherscan.io/api?module=account&action=txlist&address=0x273a4fFcEb31B8473D51051Ad2a2EdbB7Ac8Ce02&startblock=11327327&endblock=99999999&page=1&offset=10&sort=asc&apikey=YourApiKeyToken"
  // )
  //   .then((response) => response.json())
  //   .then((data) => console.log(data));
  // console.log(first);
  // const GaugeProxyV2 = await ethers.getContractAt(
  //   "/src/dill/gauge-proxies/gauge-proxy-v2.sol:GaugeProxyV2",
  //   gaugeProxyAddr
  // );
  // const length = await GaugeProxyV2.length();
  // // console.log(length);
  // await GaugeProxyV2.vote([sidechainGaugeAddr, rootGaugeMainChain],[60000, 40000]);
  // await GaugeProxyV2.distribute(0,2);
  // const AnyToken = await ethers.getContractAt(
  //   "/src/dill/anySwap/AnyswapV6ERC20.sol:AnyswapV6ERC20",
  //   AnyTokenMainAddress
  // );
  // console.log(
  //   "Any Balance of user",
  //   Number(ethers.utils.formatEther(await AnyToken.balanceOf(deployer.address)))
  // );

  // // mint token to deployer - change this to deposit of underlying;
  // // depositing underlying will mint equal number of anyTokens
  // console.log("-- Setting Minter --");
  // await AnyToken.setMinter(deployer.address);
  // console.log("-- Apply Minter --");
  // await AnyToken.applyMinter();
  // await AnyToken.mint(deployer.address, ethers.utils.parseEther("10"));
  // console.log(
  //   "Any Balance of user",
  //   Number(ethers.utils.formatEther(await AnyToken.balanceOf(deployer.address)))
  // );

  // console.log("-- wait 10 seconds --");
  // const delay = (ms) => new Promise((res) => setTimeout(res, ms));
  // await delay(10000);

  // console.log("Deployer balance => ", Number(ethers.utils.formatEther(bal)));
  // const AnyCallClient = await ethers.getContractAt(
  //   "/src/dill/anySwap/AnyCallClient.sol:AnyswapTokenAnycallClient",
  //   anyCallClientMainChain
  // );
  // console.log("-- Set distributor --");
  // await AnyCallClient.setDistributor(deployer.address);

  // console.log(" -- Sending token to side chain --");
  // const tx = await AnyCallClient.connect(deployer).bridge(
  //   AnyTokenMainAddress,
  //   ethers.utils.parseEther("1"),
  //   deployer.address,
  //   4,
  //   [1],
  //   1,
  //   {
  //     value: ethers.utils.parseEther("1"),
  //   }
  // );
  // const txData = await tx.wait();
  // // console.log(tx);
  // console.log("------------------");
  // console.log(txData);
  // console.log("------------------");
  // // console.log(txData.events.forEach(e => console.log(e)));
  // console.log(
  //   "Any Balance of sidechain",
  //   Number(ethers.utils.formatEther(await AnyToken.balanceOf(deployer.address)))
  // );

  // //   console.log(
  // //     "anyCallClientMainChain is minter ",
  // //     await AnyToken.isMinter(anyCallClientMainChain)
  // //   );

  // //   console.log("owner ", await AnyToken.owner());
  // //   console.log("Minters\n", await AnyToken.minters(0));
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
