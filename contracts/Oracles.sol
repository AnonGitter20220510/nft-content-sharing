// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "./Files.sol";

// TODO: For future work, can be expanded to not depend on Files.sol at all

contract Oracles {
	/**
	 * Enums
	 */
	enum Role {
		New,
		Deployer,
		Verifier,
		Timeout,
		Reencryptor
	}
	enum VerifyState {
		NotRequested,
		UnderVerification,
		Invalid,
		Valid
	}
	enum ReencryptState {
		NotRequested,
		LookingForReencryptor,
		UnderReencryption,
		DoneReencryption,
		UserAccept,
		UserReject
	}

	/**
	 * Structs
	 */
	struct Oracle {
		uint256 rep;
		uint256 par;
		bool lock;
	}
	struct VerifyRequest {
		uint256 timeStart; // BUG: Unused
		uint256 timeStop;
		address payable filesSC;
		uint256 rewardVerify;
		uint256 rewardTimeout;
		address[] participants;
		bool[] responses;
		uint256[] scores;
		uint256 pScoreSum;
		uint256 nScoreSum;
		bool finalized;
	}
	struct ReencryptRequest {
		uint256 timeStart;
		uint256 timeStop;
		address filesSC;
		address to;
		uint256 rewardReencrypt;
		address reencryptor;
		bool finalized;
	}

	/**
	 * Attributes
	 */
	uint256 public constant MAX_REPUTATION = 2**16;
	uint256 public constant IPNS_VERIFY_REQUEST_PERIOD = 1 hours;
	uint256 public constant FILE_VERIFY_REQUEST_PERIOD = 1 hours;
	uint256 public constant FILE_REENCRYPT_REQUEST_PERIOD = 2 hours;
	uint256 public constant FILE_REENCRYPT_MIN_REPUTATION = MAX_REPUTATION / 2;
	mapping(address => bool) public filesSC;
	mapping(address => Role) public roles;
	mapping(address => Oracle) public oracles; // NOTE: Maybe combine roles+oracles?
	mapping(address => VerifyRequest) public IPNSVRs; // BUG: n-m relationship between FilesSC and IPNS
	mapping(uint256 => VerifyRequest) public fileVRs;
	mapping(uint256 => ReencryptRequest) public fileRRs;

	/**
	 * Modifiers
	 */
	modifier only(Role _role) {
		require(roles[msg.sender] == _role, "Oracles: role not allowed");
		_;
	}
	modifier onlyFiles() {
		require(filesSC[msg.sender], "Oracles: only filesSC allowed");
		_;
	}

	/**
   * Debugging events
   */
  event print_uint256(uint256 _number);
  event print_string(string _string);
  event print_bool(bool _bool);

	/**
	 * Functions
	 */
	constructor() {
		roles[msg.sender] = Role.Deployer;
	}
	receive() external payable {}

	function registerAs(Role _role) public
		only(Role.New) {
		require(_role != Role.New && _role != Role.Deployer, "Oracles: invalid desired role");
		roles[msg.sender] = _role;
		oracles[msg.sender].rep = MAX_REPUTATION / 2;
	}

	// NOTE: Should be called automatically from Files
	function registerFiles(address _filesSC) public only(Role.Deployer) {
		filesSC[_filesSC] = true;
	}

	event NewIPNSVerifyRequest(address _filesSC, address _user);
	function startIPNSVR(address _user, uint256 _rewardVerify, uint256 _rewardTimeout) public payable
		onlyFiles() {
		require(IPNSVRs[_user].filesSC == address(0), "Oracles: already issued"); // BUG: Cannot request again for same IPNS
		IPNSVRs[_user].filesSC = payable(msg.sender);
		IPNSVRs[_user].timeStart = block.timestamp;
		IPNSVRs[_user].timeStop = block.timestamp + IPNS_VERIFY_REQUEST_PERIOD; // NOTE: Maybe add variable for timeStop
		IPNSVRs[_user].rewardVerify = _rewardVerify;
		IPNSVRs[_user].rewardTimeout = _rewardTimeout;

		emit NewIPNSVerifyRequest(msg.sender, _user);
	}
	// NOTE: Maybe revert oracles registered after certain time?
	function respondIPNSVR(address _user, bool _valid) public
		only(Role.Verifier) returns (uint256) {
		require(block.timestamp <= IPNSVRs[_user].timeStop, "Oracles: request timeout");
		require(!oracles[msg.sender].lock, "Oracles: oracle is locked");
		oracles[msg.sender].lock = true;
		IPNSVRs[_user].participants.push(msg.sender);
		IPNSVRs[_user].responses.push(_valid);
		uint256 r = oracles[msg.sender].rep;
		uint256 p = oracles[msg.sender].par;
		uint256 rmax = MAX_REPUTATION;
		uint256 ttimeout = IPNSVRs[_user].timeStop;
		uint256 tcurrent = block.timestamp;
		uint256 score = (r * p + rmax) * (ttimeout - tcurrent) / (p + 2);
		IPNSVRs[_user].scores.push(score);
		if (_valid) {
			IPNSVRs[_user].pScoreSum += score;
		} else {
			IPNSVRs[_user].nScoreSum += score;
		}
		return IPNSVRs[_user].participants.length - 1;
	}
	function finalizeIPNSVR(address _user, uint256 _i) public payable 
		only(Role.Verifier) {
		require(IPNSVRs[_user].participants[_i] == msg.sender, "Oracles: incorrect index");
		require(block.timestamp > IPNSVRs[_user].timeStop, "Oracles: too early");
		require(oracles[msg.sender].lock, "Oracles: oracle must be locked");
		oracles[msg.sender].lock = false;
		bool v = IPNSVRs[_user].responses[_i];
		uint256 pSS = IPNSVRs[_user].pScoreSum;
		uint256 nSS = IPNSVRs[_user].nScoreSum;
		uint256 mSS = pSS > nSS ? pSS : nSS;
		uint256 sn = IPNSVRs[_user].scores[_i];
		if (v == (pSS > nSS)) {
			sn += mSS;
		}
		uint256 rmax = MAX_REPUTATION;
		uint256 dr = sn * rmax / (2 * mSS);
		uint256 r = oracles[msg.sender].rep;
		uint256 p = oracles[msg.sender].par;
		r = (r * p + dr) / (p + 1);
		p += 1;
		oracles[msg.sender].rep = r;
		oracles[msg.sender].par = p;
		uint256 s = IPNSVRs[_user].scores[_i];
		uint256 f = IPNSVRs[_user].rewardVerify;
		uint256 a = f * s / mSS;
		if (v == (pSS > nSS)) {
			Address.sendValue(payable(msg.sender), a);
		}
	}
	function returnIPNSVS(address _user) public payable
		only(Role.Timeout) {
		require(block.timestamp > IPNSVRs[_user].timeStop, "Oracles: too early");
		require(!IPNSVRs[_user].finalized, "Oracles: already finalized");
		// TODO: Update reputation
		IPNSVRs[_user].finalized = true;
		Address.sendValue(payable(msg.sender), IPNSVRs[_user].rewardTimeout);
		VerifyState state = IPNSVRs[_user].pScoreSum > IPNSVRs[_user].nScoreSum ? VerifyState.Valid : VerifyState.Invalid;
		Files files = Files(IPNSVRs[_user].filesSC);
		files.setIPNSVS(_user, state);
	}

	event NewFileVerifyRequest(address _filesSC, uint256 _fileId);
	function startFileVR(uint256 _fileId, uint256 _rewardVerify, uint256 _rewardTimeout) public payable
		onlyFiles() {
		require(fileVRs[_fileId].filesSC == address(0), "Oracles: already issued"); // BUG: Cannot request again for same file
		fileVRs[_fileId].filesSC = payable(msg.sender);
		fileVRs[_fileId].timeStart = block.timestamp;
		fileVRs[_fileId].timeStop = block.timestamp + FILE_VERIFY_REQUEST_PERIOD; // NOTE: Maybe add variable for timeStop
		fileVRs[_fileId].rewardVerify = _rewardVerify;
		fileVRs[_fileId].rewardTimeout = _rewardTimeout;

		emit NewFileVerifyRequest(msg.sender, _fileId);
	}
	// NOTE: Maybe revert oracles registered after certain time?
	function respondFileVR(uint256 _fileId, bool _valid) public
		only(Role.Verifier) returns (uint256) {
		require(block.timestamp <= fileVRs[_fileId].timeStop, "Oracles: request timeout");
		require(!oracles[msg.sender].lock, "Oracles: oracle is locked");
		oracles[msg.sender].lock = true;
		fileVRs[_fileId].participants.push(msg.sender);
		fileVRs[_fileId].responses.push(_valid);
		uint256 r = oracles[msg.sender].rep;
		uint256 p = oracles[msg.sender].par;
		uint256 rmax = MAX_REPUTATION;
		uint256 ttimeout = fileVRs[_fileId].timeStop;
		uint256 tcurrent = block.timestamp;
		uint256 score = (r * p + rmax) * (ttimeout - tcurrent) / (p + 2);
		fileVRs[_fileId].scores.push(score);
		if (_valid) {
			fileVRs[_fileId].pScoreSum += score;
		} else {
			fileVRs[_fileId].nScoreSum += score;
		}
		return fileVRs[_fileId].participants.length - 1;
	}
	function finalizeFileVR(uint256 _fileId, uint256 _i) public payable 
		only(Role.Verifier) {
		require(fileVRs[_fileId].participants[_i] == msg.sender, "Oracles: incorrect index");
		require(block.timestamp > fileVRs[_fileId].timeStop, "Oracles: too early");
		require(oracles[msg.sender].lock, "Oracles: oracle must be locked");
		oracles[msg.sender].lock = false;
		bool v = fileVRs[_fileId].responses[_i];
		uint256 pSS = fileVRs[_fileId].pScoreSum;
		uint256 nSS = fileVRs[_fileId].nScoreSum;
		uint256 mSS = pSS > nSS ? pSS : nSS;
		uint256 sn = fileVRs[_fileId].scores[_i];
		if (v == (pSS > nSS)) {
			sn += mSS;
		}
		uint256 rmax = MAX_REPUTATION;
		uint256 dr = sn * rmax / (2 * mSS);
		uint256 r = oracles[msg.sender].rep;
		uint256 p = oracles[msg.sender].par;
		r = (r * p + dr) / (p + 1);
		p += 1;
		oracles[msg.sender].rep = r;
		oracles[msg.sender].par = p;
		uint256 s = fileVRs[_fileId].scores[_i];
		uint256 f = fileVRs[_fileId].rewardVerify;
		uint256 a = f * s / mSS;
		if (v == (pSS > nSS)) {
			Address.sendValue(payable(msg.sender), a);
		}
	}
	// Mint
	function returnFileVS(uint256 _fileId) public payable
		only(Role.Timeout) {
		require(block.timestamp > fileVRs[_fileId].timeStop, "Oracles: too early");
		// require(!fileVRs[_fileId].finalized, "Oracles: already finalized");
		// TODO: Update reputation
		fileVRs[_fileId].finalized = true;
		Address.sendValue(payable(msg.sender), fileVRs[_fileId].rewardTimeout);
		VerifyState state = fileVRs[_fileId].pScoreSum > fileVRs[_fileId].nScoreSum ? VerifyState.Valid : VerifyState.Invalid;
		Files files = Files(fileVRs[_fileId].filesSC);
		files.setFileVS(_fileId, state);
		delete fileVRs[_fileId]; // TODO: Can be added rather than removed
	}
	// Transfer
	function returnFileVS2(uint256 _fileId) public payable
		only(Role.Timeout) {
		require(block.timestamp > fileVRs[_fileId].timeStop, "Oracles: too early");
		// require(!fileVRs[_fileId].finalized, "Oracles: already finalized");
		// TODO: Update reputation
		fileVRs[_fileId].finalized = true;
		Address.sendValue(payable(msg.sender), fileVRs[_fileId].rewardTimeout);
		VerifyState state = fileVRs[_fileId].pScoreSum > fileVRs[_fileId].nScoreSum ? VerifyState.Valid : VerifyState.Invalid;
		Files files = Files(fileVRs[_fileId].filesSC);
		files.setFileVS2(_fileId, state);
		delete fileVRs[_fileId]; // TODO: Can be added rather than removed
	}

	event NewFileReencryptRequest(address _filesSC, uint256 _fileId);
	function startFileRE(uint256 _fileId, address _to) public payable
		onlyFiles() {
		// Requires (same fileId+from+to was not issued already, )
		// require(block.timestamp > fileRRs[_fileId].timeStop, "Oracles: reencryption ongoing");
		fileRRs[_fileId].filesSC = msg.sender;
		fileRRs[_fileId].timeStart = block.timestamp;
		fileRRs[_fileId].timeStop = block.timestamp + FILE_REENCRYPT_REQUEST_PERIOD;
		fileRRs[_fileId].to = _to;
		fileRRs[_fileId].rewardReencrypt = msg.value;
		emit NewFileReencryptRequest(msg.sender, _fileId);
	}
	function participateFileRE(uint256 _fileId) public
		only(Role.Reencryptor) {
		// Requires (min reputation)
		// require(block.timestamp <= fileRRs[_fileId].timeStop, "Oracles: request timeout");
		require(fileRRs[_fileId].reencryptor == address(0), "Oracles: already taken");
		require(!oracles[msg.sender].lock, "Oracles: oracle is locked");
		oracles[msg.sender].lock = true;
		fileRRs[_fileId].reencryptor = msg.sender;
	}
	event PrivateSession(address _reencryptor, address _to, bytes sessionId);
	function doneFileRE(uint256 _fileId) public
		only(Role.Reencryptor) {
		// require(block.timestamp <= fileRRs[_fileId].timeStop, "Oracles: request timeout");
		require(fileRRs[_fileId].reencryptor == msg.sender, "Oracles: reencryptor don't match");
		bytes memory sessionId = abi.encodePacked(fileRRs[_fileId].reencryptor, fileRRs[_fileId].to, _fileId);
		oracles[msg.sender].lock = false;
		emit PrivateSession(fileRRs[_fileId].reencryptor, fileRRs[_fileId].to, sessionId);
	}
	event print_RE(ReencryptRequest _re);
	function rateFileRE(uint256 _fileId) public payable
		onlyFiles() {
		// Requires
		// require(block.timestamp > fileRRs[_fileId].timeStop, "Oracles: too early");
		// require(!fileRRs[_fileId].finalized, "Oracles: already finalized");
		fileVRs[_fileId].finalized = true;
		delete fileRRs[_fileId]; // TODO: Can be added rather than removed
		// TODO: Update reputation
	}
	// (2) files startFileRE -> NewFileReencryptRequest
	// (3) reencryptor participateFileRE
	// (4) reencryptor doneFileRE -> PrivateSession
	// (5) files rateFileRE
}

// contract Files is ERC721URIStorage, AccessControl
//   (NFT)
//   (File)
//   (Access control)
//   (Note: Goal is to not keep track of any oracle)

// contract Verifier is Oracle
// contract Timeout is Oracle
// contract Reencryptor is Oracle
// contract Oracle
//   (Oracle tasks)

// contract Aggregator

