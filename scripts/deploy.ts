import { ethers } from "hardhat";

async function main() {
  console.log("deploying...");
  try {
    const provider = ethers.provider;
    const from = await provider.getSigner().getAddress();

    console.log("from:", from);
    const factory = await ethers.getContractFactory("Nftry");
    const usdc = "0x9758211252cE46EEe6d9685F2402B7DdcBb2466d";

    const ret = await factory.deploy(usdc);

    console.log("contract addr:", ret.address);
  } catch (e) {
    console.log(e);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
