// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./Oracles.sol";

contract Files is ERC721 {
	/**
   * Usings
   */
  using Counters for Counters.Counter;

	/**
	 * Enums
	 */
	enum Role {
		New,
		Deployer,
		User
	}

	/**
	 * Structs
	 */
	struct User {
		string IPNS;
		Oracles.VerifyState IPNSVS;
		bool lock;
		mapping(address => bool) delegates;
	}
	struct File { // NOTE: No way to add owner/tokenURI here?
		address producer;
		string path;
		string CID;
		Oracles.VerifyState ownerVS;
	}
	struct DelegatedFile {
		address owner;
		uint256 price;
	}
	struct Purchase {
		address buyer;
		uint256 price;
		bool accepted;
		bool paid;
		bool finalized;
	}
	struct License {
		address consumer;
		uint256 price;
		bool accepted;
		bool paid;
		bool finalized;
	}

	/**
	 * Attributes
	 */
	Oracles public oraclesSC;
	mapping(address => Role) public roles;
	mapping(address => User) public users;
	Counters.Counter public fileCounter;
	mapping(uint256 => File) public files;
	mapping(uint256 => DelegatedFile) public dlgFiles;
	mapping(uint256 => Purchase) public purchases;
	mapping(uint256 => License) public licenses;

	/**
	 * Modifiers
	 */
	modifier only(Role _role) {
		require(roles[msg.sender] == _role, "Files: role not allowed");
		_;
	}
	modifier onlyOracles() {
		require(msg.sender == address(oraclesSC), "Files: only oraclesSC allowed");
		_;
	}

	/**
   * Internal functions
   */
  function isEmpty(string memory _str) internal pure returns (bool) {
    return bytes(_str).length == 0;
  }
	
	/**
   * Debugging events
   */
  event print_uint256(uint256 _number);
  event print_string(string _string);
  event print_bool(bool _bool);
  event print_address(address _address);

	/**
	 * Functions
	 */
	constructor() ERC721("Files", "FILE") {
		roles[msg.sender] = Role.Deployer;
	}
	receive() external payable {}
	function setOracles(address payable _oraclesSC) public
		only(Role.Deployer) {
		oraclesSC = Oracles(_oraclesSC);
	}
	function register() public
		only(Role.New) {
		roles[msg.sender] = Role.User;
	}

	function setIPNS(string memory _IPNS, uint256 _rewardVerify, uint256 _rewardTimeout) public payable
		only(Role.User) {
		require(users[msg.sender].IPNSVS == Oracles.VerifyState.NotRequested, "Files: IPNS already set");
		require(msg.value == _rewardVerify + _rewardTimeout, "Files: rewards don't add up");
		users[msg.sender].IPNS = _IPNS;
		users[msg.sender].IPNSVS = Oracles.VerifyState.UnderVerification;
		oraclesSC.startIPNSVR{value: msg.value}(msg.sender, _rewardVerify, _rewardTimeout);
	}
	event ReceivedIPNSVS(address _user, Oracles.VerifyState _IPNSVS);
	function setIPNSVS(address _user, Oracles.VerifyState _IPNSVS) public
		onlyOracles {
		users[_user].IPNSVS = _IPNSVS;
		emit ReceivedIPNSVS(_user, _IPNSVS);
	}

	function addFile(string memory _path, string memory _CID, uint256 _rewardVerify, uint256 _rewardTimeout) public payable
		only(Role.User) {
		// Requires (valid IPNS)
		require(users[msg.sender].IPNSVS == Oracles.VerifyState.Valid, "Files: IPNS not valid");
		require(msg.value == _rewardVerify + _rewardTimeout, "Files: rewards don't add up");
		fileCounter.increment();
		uint256 fileId = fileCounter.current();
		files[fileId].producer = msg.sender;
		files[fileId].path = _path;
		files[fileId].CID = _CID;
		files[fileId].ownerVS = Oracles.VerifyState.UnderVerification;
		oraclesSC.startFileVR{value: msg.value}(fileId, _rewardVerify, _rewardTimeout);
	}
	event ReceivedFileVS(uint256 _fileId, Oracles.VerifyState _fileVS);
	function setFileVS(uint256 _fileId, Oracles.VerifyState _fileVS) public
		onlyOracles {
		files[_fileId].ownerVS = _fileVS;
		emit ReceivedFileVS(_fileId, _fileVS);
		if (_fileVS == Oracles.VerifyState.Valid) {
			_mint(files[_fileId].producer, _fileId);
		}
	}
	function setFileVS2(uint256 _fileId, Oracles.VerifyState _fileVS) public
		onlyOracles {
		files[_fileId].ownerVS = _fileVS;
		emit ReceivedFileVS(_fileId, _fileVS);
		if (_fileVS == Oracles.VerifyState.Valid) {
			_safeTransfer(ownerOf(_fileId), purchases[_fileId].buyer, _fileId, "");
		}
	}
	// TODO: Update burn method


	function addDelegate(address _delegate) public only(Role.User) {
		// Requires (_delegate is User, valid IPNS?)
		users[msg.sender].delegates[_delegate] = true;
	}
	event AddedFileFor(address _owner, uint256 _price);
	function addFileFor(address _owner, string memory _path, string memory _CID, uint256 _price) public
		only(Role.User) {
		// Requires (_owner is User + has valid IPNS, caller is valid User, is delegate)
		fileCounter.increment();
		uint256 fileId = fileCounter.current();
		files[fileId].producer = msg.sender;
		files[fileId].path = _path;
		files[fileId].CID = _CID;
		dlgFiles[fileId].owner = _owner;
		dlgFiles[fileId].price = _price;
		emit AddedFileFor(_owner, _price);
	}
	function payDelegateFor(uint256 _fileId, uint256 _rewardReencrypt) public payable
		only(Role.User) {
		// Requires (caller is intended owner, fileId is delegated, msg.value is price + rV + rT)
		Address.sendValue(payable(address(this)), dlgFiles[_fileId].price);
		oraclesSC.startFileRE{value: _rewardReencrypt}(_fileId, dlgFiles[_fileId].owner);
	}
	function acceptFile(uint256 _fileId, string memory _path, string memory _CID, uint256 _rewardVerify, uint256 _rewardTimeout) public payable
		only(Role.User) {
		// Requires
		require(msg.value == _rewardVerify + _rewardTimeout, "Files: rewards don't add up");
		files[_fileId].path = _path;
		files[_fileId].CID = _CID;
		files[_fileId].ownerVS = Oracles.VerifyState.UnderVerification;
		Address.sendValue(payable(files[_fileId].producer), dlgFiles[_fileId].price);
		oraclesSC.rateFileRE(_fileId);
		oraclesSC.startFileVR{value: msg.value}(_fileId, _rewardVerify, _rewardTimeout);
		delete dlgFiles[_fileId];
	}
	// From: Producer. To: Owner.
	// (1) owner addDelegate
	// (1.5) producer addFileFor -> AddedFileFor
	// (2) owner payDelegateFor -> startFileRE
	// (5) owner acceptFile(new path+CID)/rejectFile -> rateFileRE

	function requestPurchase(uint256 _fileId) public payable
		only(Role.User) {
		// Requires (file exists+minted, buyer has valid IPNS, no other buyer for this file?)
		purchases[_fileId].buyer = msg.sender;
		purchases[_fileId].price = msg.value;
		Address.sendValue(payable(address(this)), msg.value);
	}
	event AcceptedPurchase(uint256 _fileId, address _seller, address _buyer, uint256 _price);
	function acceptPurchase(uint256 _fileId) public only(Role.User) {
		// Requires (actual owner)
		purchases[_fileId].accepted = true;
		emit AcceptedPurchase(_fileId, msg.sender, purchases[_fileId].buyer, purchases[_fileId].price);
	}
	function payPurchaseOf(uint256 _fileId) public payable
		only(Role.User) {
		// Requires (accepted purchase, correct buyer)
		oraclesSC.startFileRE{value: msg.value}(_fileId, msg.sender);
	}
	function goodPurchase(uint256 _fileId, string memory _path, string memory _CID, uint256 _rewardVerify, uint256 _rewardTimeout) public payable
		only(Role.User) {
		// Requires (identity, parameters, state, time)
		files[_fileId].path = _path;
		files[_fileId].CID = _CID;
		files[_fileId].ownerVS = Oracles.VerifyState.UnderVerification;
		Address.sendValue(payable(ownerOf(_fileId)), purchases[_fileId].price);
		oraclesSC.startFileVR{value: msg.value}(_fileId, _rewardVerify, _rewardTimeout);
		// delete purchases[_fileId];
	}
	// From: Owner (seller). To: Owner (buyer).
	// (1) buyer requestPurchase
	// (1.5) seller acceptPurchase -> AcceptedPurchase
	// (2) buyer payPurchaseOf -> startFileRE
	// (5) buyer acceptFile(new path+CID)/rejectFile -> rateFileRE

	function requestLicense(uint256 _fileId) public payable only(Role.User) {
		// Requires
		licenses[_fileId].consumer = msg.sender;
		licenses[_fileId].price = msg.value;
		Address.sendValue(payable(address(this)), msg.value);
	}
	event AcceptedLicense(uint256 _fileId, address _owner, address _consumer, uint256 _price);
	function acceptLicense(uint256 _fileId) public only(Role.User) {
		// Requires
		licenses[_fileId].accepted = true;
		emit AcceptedLicense(_fileId, msg.sender, licenses[_fileId].consumer, licenses[_fileId].price);
	}
	function payLicenseOf(uint256 _fileId) public payable only(Role.User) {
		// Requires
		oraclesSC.startFileRE{value: msg.value}(_fileId, msg.sender);
	}
	function goodLicense(uint256 _fileId) public only(Role.User) {
		// Requires
		Address.sendValue(payable(ownerOf(_fileId)), licenses[_fileId].price);
		delete licenses[_fileId];
	}
	// From: Owner. To: Consumer.
	// (1) consumer requestLicense
	// (1.5) owner acceptLicense -> AcceptedLicense
	// (2) consumer payLicenseOf -> startFileRE
	// (5) consumer acceptFile/rejectFile -> rateFileRE
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

