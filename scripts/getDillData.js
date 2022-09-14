const { ethers } = require("ethers");
const { abi, DillAddress } = require("./config");
const fs = require("fs");

let _lastProcessedBlock = 0; // to be in DB
let provider = ethers.providers.getDefaultProvider(
  `${process.env.INFURA_RPC_URL}`
);

const DillContract = new ethers.Contract(DillAddress, abi, provider); // change signer
/**
 * function to get latest block from chain
 * @returns latestBlock Number of latest block on ethereum chain
 */
const getLatestBlock = async () => {
  let latestBlock;
  try {
    latestBlock = await provider.getBlock("latest");
    return latestBlock.number;
  } catch (error) {
    console.error(error);
    return _lastProcessedBlock; // fetch from DB and return
  }
};

/**
 * function to fetch last processed block from DB
 * @returns latest block number
 */
const getLastProcessedBlock = () => {
  let lastProcessedBlock;
  try {
    //in future fetch last processed block from DB
    lastProcessedBlock = _lastProcessedBlock;
    return lastProcessedBlock;
  } catch (error) {
    console.error(error);
  }
};

// function to store last processed block
/**
 *
 * @param {Number} block last processed block
 */
const setLastProcessedBlock = (block) => {
  //in future store in DB
  _lastProcessedBlock = block;
};

/**
 * function to fetch deposit and withdraw events from DILL contract
 * @param {Number} fromBlock start fetcheng events 'FROM' block number
 * @param {Number} toBlock fetch events 'TILL' block number
 * @returns two maps, each of deposit events and withdraw events
 */
const getDepositAndWithdrawEvents = async (fromBlock, toBlock) => {
  const depositMap = new Map();
  const withdrawMap = new Map();
  // Getting all deposit events
  let eventFilterDeposit = DillContract.filters.Deposit();
  let depositEvents = await DillContract.queryFilter(
    eventFilterDeposit,
    fromBlock,
    toBlock
  );

  // set deposit events into map
  depositEvents.forEach((e) => {
    depositMap.set(e.args[0], {
      provider: e.args[0],
      value: depositMap.get(e.args[0])
        ? depositMap.get(e.args[0]).value.add(e.args[1])
        : e.args[1],
      locktime: e.args[2],
      type: e.args[3],
      ts: e.args[4],
    });
  });

  // Getting all withdraw events
  let eventFilterWithdraw = DillContract.filters.Withdraw();
  let withdrawEvents = await DillContract.queryFilter(
    eventFilterWithdraw,
    fromBlock,
    toBlock
  );

  //set withdraw events into map
  withdrawEvents.forEach((e) => {
    withdrawMap.set(e.args[0], {
      provider: e.args[0],
      value: withdrawMap.get(e.args[0])
        ? withdrawMap.get(e.args[0]).value.add(e.args[1])
        : e.args[1],
      ts: e.args[2],
    });
  });

  return { depositMap, withdrawMap };
};

/**
 *
 * @param {Map} depositMap Mapped deposit events
 * @param {Map} withdrawMap Mapped withdraw events
 * @returns Mapped data of users to there locked pickle amount
 */
const processEventsData = (depositMap, withdrawMap) => {
  // Get locked pickle holder address
  const pickleBalance = new Map();
  depositMap.forEach((e) => {
    const balance = e.value.sub(
      withdrawMap.get(e.provider) ? withdrawMap.get(e.provider).value : 0
    );
    balance
      ? pickleBalance.set(e.provider, {
          balance: balance,
        })
      : "";
  });
  return pickleBalance;
};

/**
 *
 * @param {Map} pickleBalance Map of pickleBalances from processEventsData()
 * @param {*} block block number to get dill balance at
 * @returns Mapped dill balances of users
 */
const getDillBalances = async (pickleBalanceMap, block) => {
  //get dill balances
  const dillBalance = new Map();
  const itrator = pickleBalanceMap.keys();
  for (let i = 0; i < pickleBalanceMap.size; i++) {
    const key = itrator.next().value;
    const balance = await DillContract.balanceOfAt(key, block);
    dillBalance.set(key, {
      balance: balance,
    });
  }
  return dillBalance;
};

const delay = (ms) => new Promise((res) => setTimeout(res, ms));

const main = async () => {
  let dillBalances = new Map();
  let depositMap = new Map();
  let withdrawMap = new Map();
  let pickleBalance = new Map();
  while (true) {
    try {
      let latestBlock = await getLatestBlock();
      let lastProcessedBlock = getLastProcessedBlock();

      if (lastProcessedBlock < latestBlock) {
        ({ depositMap, withdrawMap } = await getDepositAndWithdrawEvents(
          lastProcessedBlock,
          latestBlock
        ));

        // get all dill holders
        pickleBalance = processEventsData(depositMap, withdrawMap);

        // get dill balances
        dillBalances = await getDillBalances(pickleBalance, latestBlock);
        const dillBalancesData = JSON.stringify([...dillBalances], null, 2);

        fs.writeFileSync("DILLBalances.json", dillBalancesData); // in future store this in DB

        setLastProcessedBlock(latestBlock);
      } else {
        await delay(2000); // 2 seconds delay for infura call/second issue
      }
    } catch (error) {
      console.error(error);
    }
  }
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
