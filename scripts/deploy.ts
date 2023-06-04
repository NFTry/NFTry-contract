import { ethers } from "hardhat";

async function main() {
  console.log("deploying...");
  try {
    const provider = ethers.provider;
    const from = await provider.getSigner().getAddress();

    console.log("from:", from);
    const factory = await ethers.getContractFactory("NFTRY");
    const ret = await factory.deploy();

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
