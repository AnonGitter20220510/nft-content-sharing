# POC for NFT-based Content Sharing and Monetization

Project is at review stage.

## Usage

1. Install [ganache-cli](https://www.npmjs.com/package/ganache) (tested up to version `@7.0.3`)
	```console
	npm i -g ganache
	```
2. Install [truffle](https://www.npmjs.com/package/truffle) (tested up to version `@5.5.5`)
	```console
	npm i -g truffle
	```
3. Run `ganache --miner.defaultTransactionGasLimit="1000000" --wallet.totalAccounts="17"` and keep console running
4. Open a new console and move (`cd`) to appropriate directory
5. Clone project `git clone https://github.com/AnonGitter20220510/nft-content-sharing.git` and move to project directory (`cd nft-content-sharing`)
6. Run `truffle test --show-events`
