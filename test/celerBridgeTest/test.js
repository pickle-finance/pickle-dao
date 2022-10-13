// ftm test => rinkeby
const { ethers } = require("hardhat");

const tempPickleMain = "0x1Fcf02E6C31f3De71E7d164AC0e7fC3CaFDC0E38";
const CelerClientMainAddress = "0x90D538408E82cB99fEc827B0B881072cd4E488d3";
// const CelerClientMainAddress1 = "0x236CB0Ebe73d8D993b73B8BA6d18268fb08Fc398";
const CelerTokenMainAddress = "0xE0c8e1De45b2C7A07E884aB52Acd3dC92EED5c7e";
const CelerClientSideChain = "0x82cfA4a43AdBC656806Ef7837aaD00Ad44e24dD8";
const CelerTokenSideAddress = "0x839C479c8de1e1038deB2DCd1e4780f0C45Cd284";
const tempPickleSide = "0x7bd365550A2C4714c2C5Bdf2B1D9D35750FCeB32";


const main = async () => {
    const [deployer] = await ethers.getSigners();
    // console.log("Deploying Temp Pickle");
    // const tempPickle = await ethers.getContractFactory("TempPickle");
    // const TempPickle = await tempPickle.deploy(ethers.utils.parseEther('10000000'));
    // await TempPickle.deployed();
    // console.log("Temp Pickle Deployed At : ", TempPickle.address);


    //   console.log("Deploying Celer Token");
    //   const celerToken = await ethers.getContractFactory("CelerERC20");
    //   const CelerToken = await celerToken.deploy("ANY PICKLE", "AP", 18, tempPickleMain, deployer.address); // change underlying
    //   await CelerToken.deployed();
    //   console.log("Celer token deployed : ", CelerToken.address);

    //   const celerClient = await ethers.getContractFactory("CelerClient");
    //   const CelerClient = await celerClient.deploy("0xb92d6933A024bcca9A21669a480C236Cbc973110");
    //   await CelerClient.deployed();
    //   console.log("Celer deployed at :" , CelerClient.address);

    const CelerClient = await ethers.getContractAt("src/dill/celer/CelerClient.sol:CelerClient", CelerClientMainAddress);
    console.log("CelerClient listening at :", CelerClient.address);


    const CelerToken = await ethers.getContractAt("src/dill/celer/CelerERC20.sol:CelerERC20", CelerTokenMainAddress);
    console.log("CelerTOken listening at :", CelerToken.address);

    //   console.log("-- Setting Minter --");
    //   await CelerToken.setMinter(CelerClient.address);
    //   const delay = ms => new Promise(res => setTimeout(res, ms));
    //   await delay(10000);
    //   console.log("-- Apply Minter --");
    //   await CelerToken.applyMinter();


    //   await CelerClient.setClientPeers([5], [CelerClientSideChain]); //fantom
    //   await CelerClient.setTokenPeers(CelerTokenMainAddress, [5], [CelerTokenSideAddress]); //anytoken

    const tempPickle = await ethers.getContractAt(
        "src/dill/celer/TempPickle.sol:TempPickle",
        tempPickleMain
    );


    // //    await tempPickle.approve(CelerClient.address, 100000);
    //    let allow = await tempPickle.allowance(deployer.address, CelerClient.address);
    //    console.log("allowance", allow);


    // console.log("maintoken", await tempPickle.balanceOf(CelerTokenMainAddress));
    //  console.log(await CelerToken.underlying());
    // console.log("maindeployer", await tempPickle.balanceOf(deployer.address));
    // console.log("Celer balance :", await CelerToken.balanceOf(deployer.address));
    // console.log("mainCleint", await tempPickle.balanceOf(CelerClientMainAddress));
    //     await CelerClient.mintCelerToken(CelerToken.address);
    // console.log(await CelerToken.balanceOf(CelerClient.address));



   

    const tx = await CelerClient.connect(deployer).bridge(
      CelerToken.address,
      100,
      deployer.address,
      5,
      [1],
      1, {
      value: ethers.utils.parseEther('0.00000000001'),
  }
  );
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });


  //   console.log("-- Set distributor --");
  //   await CelerClient.setDistributor(deployer.address);