// ftm test => rinkeby
const { ethers } = require("hardhat");
const hre = require("hardhat");

// const AnyTokenMainAddress = "0x7d05fF0b2b21De07ba6d4Cdb4FB461921Ad05Ef3";
// const AnyTokenMainAddress = "0x00854A64CA26a7ECC4c05D3Ba07aF702f697F6fA";
// const anyCallClientMainChain = "0x9E532775e2be44D6DD7FF2dC75687F832a26f06f";
// const AnyTokenSideAddress = "0x380056c861CdF4F3C5e0281Fcc43154E5E83b2E6";
// const anyCallClientSideChain = "0x363e0d9720d897Be38ef6d0E1D7F9ACbFD9D9Ea5";

// const tempPickleMainChain = "0x5865228c6b543CE8e3883890fCCA81f3178b5dDa";
const tempPickleSideChain = "0x5C8fB573708b3ecFBF2Aaf33Cc04872725cd8bf2";
const sideChainGaugeProxyAddr = "0x3cAb076A66b1487B4A5fb7fE53175Ba672644642";
const gauge1Adr = "0x526e4ECa985A6E837c5fBdE30dE57a36Ba0fc2Ca";
const gauge2Adr = "0x23708ec7448F81434E7Bdaa4D131657450F57095";
// const rootGaugeMainChain = "0xacD722b2bdb270fB37Adc0a2889BaBB7d82fcff8";

const main = async () => {
  const TempPickle = await ethers.getContractAt(
    "/src/yield-farming/pickle-token.sol:PickleToken",
    tempPickleSideChain
  );
  const SidechainGaugeProxy = await ethers.getContractAt(
    "/src/dill/gauge-proxies/sidechain-gauge-proxy.sol:SidechainGaugeProxy",
    sideChainGaugeProxyAddr
  );
  const [deployer] = await ethers.getSigners();
  const bal = await ethers.provider.getBalance(deployer.address);

  // //////////////////////////////////////////////////

  //  console.log(
  //     "user tempPickle Balance => ",
  //     Number(
  //       ethers.utils.formatEther(await TempPickle.balanceOf(deployer.address))
  //     )
  //   );
  //   console.log("approving pickle ");
  //   await TempPickle.approve(
  //     SidechainGaugeProxy.address,
  //     ethers.utils.parseEther("100")
  //   );
  //   console.log(
  //     "pickle allowance of sidechainGaugeProxy =>",
  //     Number(
  //       ethers.utils.formatEther(
  //         await TempPickle.allowance(
  //           deployer.address,
  //           SidechainGaugeProxy.address
  //         )
  //       )
  //     )
  //   );
  //   console.log("sending reward to sideChainGaugeProxy");
  //   await SidechainGaugeProxy.sendRewards(
  //     3,
  //     ethers.utils.parseEther("100"),
  //     [30000, 70000],
  //     {
  //       gasLimit: 9000000,
  //     }
  //   );
  //   // await SidechainGaugeProxy.distribute(0,2);

  //   console.log(
  //     "sideChainGaugeProxy tempPickle Balance => ",
  //     Number(
  //       ethers.utils.formatEther(
  //         await TempPickle.balanceOf(SidechainGaugeProxy.address)
  //       )
  //     )
  //   );

  ////////////////////////////////////////////////////////////////////////////

  const XYZgaugeV2 = await ethers.getContractAt(
    "/src/dill/gauges/GaugeV2.sol:GaugeV2",
    gauge1Adr
  );
  const gaugeV2 = await ethers.getContractAt(
    "/src/dill/gauges/GaugeV2.sol:GaugeV2",
    gauge2Adr
  );

  // XYZgaugeV2.setRewardToken(tempPickleSideChain, sideChainGaugeProxyAddr);
  // gaugeV2.setRewardToken(tempPickleSideChain, sideChainGaugeProxyAddr);

  // console.log(await XYZgaugeV2.rewardTokenDetails(tempPickleSideChain));
  // console.log(await gaugeV2.rewardTokenDetails(tempPickleSideChain));
  console.log(
    "sideChainGaugeProxy tempPickle Balance => ",
    Number(
      ethers.utils.formatEther(
        await TempPickle.balanceOf(sideChainGaugeProxyAddr)
      )
    )
  );

  // await sidechainGaugeProxy.sendRewards(1, 100, [30000, 70000]);
  await SidechainGaugeProxy.distribute(0, 2);

  console.log(
    "pickle balance of gauge 1 =>",
    Number(ethers.utils.formatEther(await TempPickle.balanceOf(gauge1Adr)))
  );
  console.log(
    "pickle balance of gauge 1 =>",
    Number(ethers.utils.formatEther(await TempPickle.balanceOf(gauge2Adr)))
  );
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
//[ '0xe2146935', '0x9abaf479' ],0xa35fe8bf
