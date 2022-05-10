const Oracles = artifacts.require("Oracles");
const Files = artifacts.require("Files");

async function getFees(resp) {
	let transactionGasUsed = resp.receipt.gasUsed;
	let transactionGasPrice = (await web3.eth.getTransaction(resp.tx)).gasPrice;
	let transactionFees = web3.utils.toBN(transactionGasUsed * transactionGasPrice);
	return transactionFees;
}
async function logTransfer(from, to, func) {
	let fromBalBefore = web3.utils.toBN(await web3.eth.getBalance(from));
	let toBalBefore = web3.utils.toBN(await web3.eth.getBalance(to));
	let resp = await func();
	let fromBalAfter = web3.utils.toBN(await web3.eth.getBalance(from));
	let toBalAfter = web3.utils.toBN(await web3.eth.getBalance(to));
	let txnFees = web3.utils.toBN(await getFees(resp));
	return {
		resp,
		from: {
			before: fromBalBefore.toString(),
			after: fromBalAfter.toString(),
			paidAll: fromBalBefore.sub(fromBalAfter).toString(),
			paidAmount: fromBalBefore.sub(fromBalAfter).sub(txnFees).toString(),
			paidFees: txnFees.toString()
		},
		to: {
			before: toBalBefore.toString(),
			after: toBalAfter.toString(),
			receivedAmount: toBalAfter.sub(toBalBefore).toString()
		}
	}
}
async function getTransactionTime(resp) {
	return await (await web3.eth.getBlock(resp.receipt.blockNumber)).timestamp;
}
// https://stackoverflow.com/a/65885395
function evmIncreaseTime(seconds) {
	return new Promise((resolve, reject) => {
		web3.currentProvider.send({
			method: "evm_increaseTime",
			params: [seconds],
			jsonrpc: "2.0",
			id: new Date().getTime()
		}, (error, result) => {
			if (error) {
					return reject(error);
			}
			return resolve(result);
		});
	}); 
}

// ganache --miner.defaultTransactionGasLimit="1000000" --wallet.totalAccounts="20"
// truffle test --show-events

contract("Testing registration and upload", async accounts => {
	let oracles, files;
	let oDep = accounts[0];
	let fDep = accounts[1];
	let usr = [accounts[2], accounts[3], accounts[4]];
	let vrf = [accounts[5], accounts[6], accounts[7],
						 accounts[8], accounts[9], accounts[10]];
	let tmo = [accounts[11], accounts[12], accounts[13]];
	let ree = [accounts[14], accounts[15], accounts[16]];

	let gu = {
		setOracles       : [],
		registerFiles    : [],
		register         : [],
		registerAs       : [],
		setIPNS          : [],
		respondIPNSVR    : [],
		finalizeIPNSVR   : [],
		returnIPNSVS     : [],
		addFile          : [],
		respondFileVR    : [],
		finalizeFileVR   : [],
		returnFileVS     : [],
		addDelegate      : [],
		addFileFor       : [],
		payDelegate      : [],
		participateFileRE: [],
		doneFileRE       : [],
		acceptFile       : [],
		requestPurchase  : [],
		acceptPurchase   : [],
		payPurchase      : [],
		finalizePurchase : [],
		requestLicense   : [],
		acceptLicense    : [],
		payLicense       : [],
		finalizeLicense  : []
	};

	beforeEach(async () => {
		oracles = await Oracles.deployed({from: oDep});
		files = await Files.deployed(oracles.address, {from: fDep});
	});

	it("Connect Oracles and Files", async () => {
		var resp;
		
		resp = await files.setOracles(oracles.address, {from: fDep}); gu.setOracles.push(resp.receipt.gasUsed);
		resp = await oracles.registerFiles(files.address, {from: oDep}); gu.registerFiles.push(resp.receipt.gasUsed);
	});

	it("Register users", async () => {
		var resp;

		resp = await files.register({from: usr[0]}); gu.register.push(resp.receipt.gasUsed);
		resp = await files.register({from: usr[1]}); gu.register.push(resp.receipt.gasUsed);
		resp = await files.register({from: usr[2]}); gu.register.push(resp.receipt.gasUsed);
	});
	it("Register oracles", async () => {
		var resp;

		resp = await oracles.registerAs(2, {from: vrf[0]}); gu.registerAs.push(resp.receipt.gasUsed);
		resp = await oracles.registerAs(2, {from: vrf[1]}); gu.registerAs.push(resp.receipt.gasUsed);
		resp = await oracles.registerAs(2, {from: vrf[2]}); gu.registerAs.push(resp.receipt.gasUsed);
		resp = await oracles.registerAs(2, {from: vrf[3]}); gu.registerAs.push(resp.receipt.gasUsed);
		resp = await oracles.registerAs(2, {from: vrf[4]}); gu.registerAs.push(resp.receipt.gasUsed);
		resp = await oracles.registerAs(2, {from: vrf[5]}); gu.registerAs.push(resp.receipt.gasUsed);
		
		resp = await oracles.registerAs(3, {from: tmo[0]}); gu.registerAs.push(resp.receipt.gasUsed);
		resp = await oracles.registerAs(3, {from: tmo[1]}); gu.registerAs.push(resp.receipt.gasUsed);
		resp = await oracles.registerAs(3, {from: tmo[2]}); gu.registerAs.push(resp.receipt.gasUsed);
		
		resp = await oracles.registerAs(4, {from: ree[0]}); gu.registerAs.push(resp.receipt.gasUsed);
		resp = await oracles.registerAs(4, {from: ree[1]}); gu.registerAs.push(resp.receipt.gasUsed);
		resp = await oracles.registerAs(4, {from: ree[2]}); gu.registerAs.push(resp.receipt.gasUsed);
	});

	it("Set IPNS for usr0", async () => {
		var resp;

		let reward = web3.utils.toBN(web3.utils.toWei('0.2'));
		let rewardVerifier = web3.utils.toBN(web3.utils.toWei('0.15'));
		let rewardTimeout = web3.utils.toBN(web3.utils.toWei('0.05'));
		resp = await files.setIPNS("0x123", rewardVerifier, rewardTimeout, {from: usr[0], value: reward}); gu.setIPNS.push(resp.receipt.gasUsed);
	});
	it("Verify usr0 IPNS (valid)", async () => {
		var resp;

		let delays = [2, 8, 5, 15, 20, 5, 5];
		let responses = [true, false, true, false, false, false];
		let index = [4, 2, 1, 0, 5, 3];
		for (i = 0; i < 6; i++) {
			await evmIncreaseTime(60 * delays[i]);
			resp = await oracles.respondIPNSVR(usr[0], responses[i], {from: vrf[index[i]]}); gu.respondIPNSVR.push(resp.receipt.gasUsed);
		}
		await evmIncreaseTime(60 * delays[6] + 1);
		for (i = 0; i < 6; i++) {
			resp = await oracles.finalizeIPNSVR(usr[0], i, {from: vrf[index[i]]}); gu.finalizeIPNSVR.push(resp.receipt.gasUsed);
		}
		resp = await oracles.returnIPNSVS(usr[0], {from: tmo[0]}); gu.returnIPNSVS.push(resp.receipt.gasUsed);
		// resp = await logTransfer(oracles.address, tmo[0], async () => {
		// 	return await oracles.returnIPNSVS(usr[0], {from: tmo[0]});
		// });
		// console.log({from: resp.from, to: resp.to});
	});

	it("Add file1 for usr0", async () => {
		var resp;

		let rewardVerifier = web3.utils.toBN(web3.utils.toWei('0.3'));
		let rewardTimeout = web3.utils.toBN(web3.utils.toWei('0.1'));
		let reward = rewardVerifier.add(rewardTimeout);
		resp = await files.addFile("img1.png", "baf123", rewardVerifier, rewardTimeout, {from: usr[0], value: reward}); gu.addFile.push(resp.receipt.gasUsed);
	});
	it("Verify file1 (valid)", async () => {
		var resp;

		let delays = [15, 2, 5, 1, 27, 5, 5];
		let responses = [false, true, true, true, false, false];
		let index = [2, 1, 4, 5, 3, 0];
		for (i = 0; i < 6; i++) {
			await evmIncreaseTime(60 * delays[i]);
			resp = await oracles.respondFileVR(1, responses[i], {from: vrf[index[i]]}); gu.respondFileVR.push(resp.receipt.gasUsed);
		}
		await evmIncreaseTime(60 * delays[6] + 1);
		for (i = 0; i < 6; i++) {
			resp = await oracles.finalizeFileVR(1, i, {from: vrf[index[i]]}); gu.finalizeFileVR.push(resp.receipt.gasUsed);
		}
		resp = await oracles.returnFileVS(1, {from: tmo[1]}); gu.returnFileVS.push(resp.receipt.gasUsed);
	});
	
	it("Add usr1 as delegate and add file2", async () => {
		var resp;

		resp = await files.addDelegate(usr[1], {from: usr[0]}); gu.addDelegate.push(resp.receipt.gasUsed);
		let price = web3.utils.toBN(web3.utils.toWei('0.6'));
		resp = await files.addFileFor(usr[0], "doc2_1.pdf", "0x987_1", price, {from: usr[1]}); gu.addFileFor.push(resp.receipt.gasUsed);
		let reward = web3.utils.toBN(web3.utils.toWei('0.2'));
		let fees = await price.add(reward);
		resp = await files.payDelegateFor(2, reward, {from: usr[0], value: fees}); gu.payDelegate.push(resp.receipt.gasUsed);
	});
	it("Reencrypt and accept file2", async () => {
		var resp;

		await evmIncreaseTime(60 * 3);
		resp = await oracles.participateFileRE(2, {from: ree[0]}); gu.participateFileRE.push(resp.receipt.gasUsed);
		await evmIncreaseTime(60 * 7);
		resp = await oracles.doneFileRE(2, {from: ree[0]}); gu.doneFileRE.push(resp.receipt.gasUsed);
		let rewardVerifier = web3.utils.toBN(web3.utils.toWei('0.2'));
		let rewardTimeout = web3.utils.toBN(web3.utils.toWei('0.15'));
		let reward = rewardVerifier.add(rewardTimeout);
		resp = await files.acceptFile(2, "doc2_0.pdf", "0x987_0", rewardVerifier, rewardTimeout, {from: usr[0], value: reward}); gu.acceptFile.push(resp.receipt.gasUsed);
	});
	it("Verify file2 (valid)", async () => {
		var resp;

		let delays = [5, 15, 5, 5, 15, 10, 5];
		let responses = [false, true, true, true, false, false];
		let index = [3, 2, 1, 0, 5, 4];
		for (i = 0; i < 6; i++) {
			await evmIncreaseTime(60 * delays[i]);
			resp = await oracles.respondFileVR(2, responses[i], {from: vrf[index[i]]}); gu.respondFileVR.push(resp.receipt.gasUsed);
		}
		await evmIncreaseTime(60 * delays[6] + 1);
		for (i = 0; i < 6; i++) {
			resp = await oracles.finalizeFileVR(2, i, {from: vrf[index[i]]}); gu.finalizeFileVR.push(resp.receipt.gasUsed);
		}
		resp = await oracles.returnFileVS(2, {from: tmo[2]}); gu.returnFileVS.push(resp.receipt.gasUsed);
	});

	it("Request and accept purchase of file1", async () => {
		var resp;

		let price = web3.utils.toBN(web3.utils.toWei('3'));
		resp = await files.requestPurchase(1, {from: usr[2], value: price}); gu.requestPurchase.push(resp.receipt.gasUsed);
		resp = await files.acceptPurchase(1, {from: usr[1]}); gu.acceptPurchase.push(resp.receipt.gasUsed);
		let reward = web3.utils.toBN(web3.utils.toWei('0.2'));
		resp = await files.payPurchaseOf(1, {from: usr[2], value: reward}); gu.payPurchase.push(resp.receipt.gasUsed);
	});
	it("Reencrypt and accept purchase of file1", async () => {
		var resp;

		await evmIncreaseTime(60 * 3);
		resp = await oracles.participateFileRE(1, {from: ree[1]}); gu.participateFileRE.push(resp.receipt.gasUsed);
		await evmIncreaseTime(60 * 7);
		resp = await oracles.doneFileRE(1, {from: ree[1]}); gu.doneFileRE.push(resp.receipt.gasUsed);
		let rewardVerifier = web3.utils.toBN(web3.utils.toWei('0.2'));
		let rewardTimeout = web3.utils.toBN(web3.utils.toWei('0.15'));
		let reward = rewardVerifier.add(rewardTimeout);
		resp = await files.goodPurchase(1, "img1_2.png", "0x123_2", rewardVerifier, rewardTimeout, {from: usr[2], value: reward}); gu.finalizePurchase.push(resp.receipt.gasUsed);
	});
	it("Verify purchased file1 (valid)", async () => {
		var resp;

		let delays = [30, 5, 3, 12, 2, 3, 5];
		let responses = [true, true, true, false, false, false];
		let index = [2, 3, 4, 5, 0, 1];
		for (i = 0; i < 6; i++) {
			await evmIncreaseTime(60 * delays[i]);
			resp = await oracles.respondFileVR(1, responses[i], {from: vrf[index[i]]}); gu.respondFileVR.push(resp.receipt.gasUsed);
		}
		await evmIncreaseTime(60 * delays[6] + 1);
		for (i = 0; i < 6; i++) {
			resp = await oracles.finalizeFileVR(1, i, {from: vrf[index[i]]}); gu.finalizeFileVR.push(resp.receipt.gasUsed);
		}
		resp = await oracles.returnFileVS2(1, {from: tmo[2]}); gu.returnFileVS.push(resp.receipt.gasUsed);
	});

	it("Request and accept license of file2", async () => {
		var resp;

		let price = web3.utils.toBN(web3.utils.toWei('0.7'));
		resp = await files.requestLicense(2, {from: usr[2], value: price}); gu.requestLicense.push(resp.receipt.gasUsed);
		resp = await files.acceptLicense(2, {from: usr[0]}); gu.acceptLicense.push(resp.receipt.gasUsed);
		let reward = web3.utils.toBN(web3.utils.toWei('0.2'));
		resp = await files.payLicenseOf(2, {from: usr[2], value: reward}); gu.payLicense.push(resp.receipt.gasUsed);
	});
	it("Reencrypt and accept license of file2", async () => {
		var resp;

		await evmIncreaseTime(60 * 3);
		resp = await oracles.participateFileRE(2, {from: ree[0]}); gu.participateFileRE.push(resp.receipt.gasUsed);
		await evmIncreaseTime(60 * 7);
		resp = await oracles.doneFileRE(2, {from: ree[0]}); gu.doneFileRE.push(resp.receipt.gasUsed);
		resp = await files.goodLicense(1, {from: usr[2]}); gu.finalizeLicense.push(resp.receipt.gasUsed);
		
	});
	it("Measuring average gas used", async () => {
		for (var fn of Object.keys(gu)) {
			console.log(fn + ": " + gu[fn].reduce((a,c) => a + c, 0) / gu[fn].length);
		}
	});
});