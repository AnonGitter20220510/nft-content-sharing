const Oracles = artifacts.require("Oracles");
const Files = artifacts.require("Files");

module.exports = async (deployer, network, accounts) => {
  deployer.deploy(Oracles, {from: accounts[0]});
  deployer.link(Oracles, Files);
  deployer.deploy(Files, {from: accounts[1]});
};
