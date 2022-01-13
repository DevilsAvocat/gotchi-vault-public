//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IERC173.sol";
import "./interfaces/IERC1155.sol";
import "./interfaces/StakingContract.sol";
import "./interfaces/Raffle.sol";
import "./interfaces/IAavegotchi.sol";
import "./vGHST.sol";

import "hardhat/console.sol";


// All state variables are accessed through this struct
// To avoid name clashes and make clear a variable is a state variable
// state variable access starts with "s." which accesses variables in this struct
struct AppStorage {
    // IERC165
    mapping(bytes4 => bool) supportedInterfaces;
    address contractOwner;
    address contractCreator;
    address vGHSTAddress;

    //every ERC721 token is mapped to a depositor address
    //the default (i.e., the token hasn't been deposited) maps to the 0 address
    mapping(address => mapping(uint256 => address)) deposits; 
    //every depositor is mapped to an array of their tokens
    mapping(address=>mapping(address=>uint256[])) tokenIdsByOwner;
    //each token index is mapped to ensure constant tokenId look-ups and avoid iteration
    //this is a lot (triple mapping) but it ends up being ownerTokenIndexByTokenId[_tokenAddress][_user][tokenId]
    mapping(address=>mapping(address => mapping(uint256 => uint256))) ownerTokenIndexByTokenId;

    mapping(uint256 => Gotchi) gotchiMapping;

    //the fee we're going to charge on all GHST deposits/withdrawals
    uint256 feeBP;
    //the fee we're going to charge on all erc721 deposits/withdrawals
    uint256 fee721;

    uint256 totalFeesCollected;
}

struct Gotchi {

    address DepositorAddress;
    uint256 tokenId;

    uint256 timeCheckedOut;

    //rental details
    /*uint256 _amountPerDay,
    uint256 _period,
    uint256[3] calldata _revenueSplit,
    address _receiver,
    uint256 _whitelistId*/

}

//This contract allows users to deposit their Aavegotchis (and potentially other tokens) into the Gotchi Vault.  Once deposited,
//the aavegotchis are auto-pet.
contract GotchiVault is IERC173, Initializable,PausableUpgradeable, IERC721ReceiverUpgradeable, IERC1155ReceiverUpgradeable {

    using SafeMath for uint256;

    // State variables are prefixed with s.
    AppStorage internal s;
    // Immutable values are prefixed with im_ to easily identify them in code
    // these are constant not immutable because this upgradeable contract doesn't have a constructor
    // (immutable variables must be declared in the constructor -- i like the im prefix though)
    address internal constant im_diamondAddress = 0x86935F11C86623deC8a25696E1C19a8659CbF95d;
    address internal constant im_ghstAddress = 0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7;
    //address internal constant im_vGHSTAddress;
    address internal constant im_realmAddress = 0x1D0360BaC7299C86Ec8E99d0c1C9A95FEfaF2a11;
    address internal constant im_raffleAddress = 0x6c723cac1E35FE29a175b287AE242d424c52c1CE;
    address internal constant im_stakingAddress = 0xA02d547512Bb90002807499F05495Fe9C4C3943f;

    bytes4 internal constant ERC1155_ACCEPTED = 0xf23a6e61; // Return value from `onERC1155Received` call if a contract accepts receipt (i.e `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`).
    uint256 internal constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function initialize(
        address _contractOwner,
        address _vGHST,
        uint256 _feeBP,
        uint256 _fee721
        ) public initializer{

        s.contractOwner = _contractOwner;
        s.contractCreator = _contractOwner;
        s.vGHSTAddress = _vGHST;
        s.feeBP = _feeBP;
        s.fee721 = _fee721;

        IAavegotchi(im_diamondAddress).setApprovalForAll(im_diamondAddress, true);
        StakingContract(im_stakingAddress).setApprovalForAll(im_raffleAddress, true);
        IERC20(im_ghstAddress).approve(im_stakingAddress, MAX_INT);
        ERC20(im_ghstAddress).approve(_vGHST, MAX_INT);
    }

    function getTokenIdsOfDepositor(address _depositor,address _tokenAddress) public view returns(uint256[] memory){
        return s.tokenIdsByOwner[_tokenAddress][_depositor];
    }

    function getDepositors() public view returns(address[] memory){

        uint32[] memory myGotchis = IAavegotchi(im_diamondAddress).tokenIdsOfOwner(address(this));

        address[] memory _depositors = new address[](myGotchis.length);

        for(uint256 i = 0; i < myGotchis.length; i++){
            _depositors[i] = s.deposits[im_diamondAddress][myGotchis[i]];
        }

        return _depositors;
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //In this section we have functions that can be called by the owner to control the contract

    function setFee(uint256 _newFeeBP) public onlyOwner{
        s.feeBP = _newFeeBP;
    }

    function getFee() public view returns(uint256){
        return s.feeBP;
    }

    function setFee721(uint256 _newFee721) public onlyOwner{
        s.fee721 = _newFee721;
    }

    function getFee721() public view returns(uint256){
        return s.fee721;
    }

    function getTotalFees() public view returns(uint256){
        return s.totalFeesCollected;
    }

    function setApprovals() public onlyOwner{

        IAavegotchi(im_diamondAddress).setApprovalForAll(im_diamondAddress, true);
        StakingContract(im_stakingAddress).setApprovalForAll(im_raffleAddress, true);
        IERC20(im_ghstAddress).approve(im_stakingAddress, MAX_INT);
        IERC20(im_ghstAddress).approve(address(this), MAX_INT);
                
    }

    function pause() public onlyOwner whenNotPaused () {
        _pause();
    }

    function unpause() public onlyOwner whenPaused () {
        _unpause();
    }

    function setPetOperatorForAll(address _operator, bool _approved) public onlyOwner {
        IAavegotchi(im_diamondAddress).setPetOperatorForAll(_operator, _approved);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //In this section we have wrapper functions allowing the user to do things with their staked tokens
    //Allow users to withdraw the escrow from their gotchi
    function transferEscrow(uint256 _tokenId, address _erc20Contract, address _recipient, uint256 _transferAmount) public whenNotPaused{
        require(s.deposits[im_diamondAddress][_tokenId] == msg.sender, "Only owner can withdraw escrow!");
        
        //withdraw the escrow to "this" and then send along (taking out fee) to end user
        IAavegotchi(im_diamondAddress).transferEscrow(_tokenId, _erc20Contract, address(this), _transferAmount);
        sendERC20withFee(_erc20Contract,_transferAmount, _recipient);

    }

    /////////////////////////////////////////////////////////////////////////////////////
    //Misc. wrapper functions -- interact, spend skill points
    function interact(uint256[] calldata _tokenIds) public whenNotPaused{
        IAavegotchi(im_diamondAddress).interact(_tokenIds);
    }

    function spendSkillPoints(uint256 _tokenId, int16[4] calldata _values) public whenNotPaused{ 

        require(s.deposits[im_diamondAddress][_tokenId] == msg.sender, "Only owner can call!");

        IAavegotchi(im_diamondAddress).spendSkillPoints(_tokenId, _values);
    }


    /////////////////////////////////////////////////////////////////////////////////////
    //In this section, we allow users to deposit and withdraw their ERC721 tokens
    //todo: only charge on first deposit of a gotchi?
    function depositERC721(address _tokenAddress, uint256[] calldata _tokenId) public whenNotPaused {
        require(_tokenId.length <= 10, "Fail: can only submit 10 gotchis at a time");

        //start out waiving the deposit fee -- we'll go through each gotchi and see if we should charge a fee
        bool waiveFee = true;

        for(uint256 i = 0; i<_tokenId.length; i++){

            //we track that this user deposited this specific ERC721 token
            s.deposits[_tokenAddress][_tokenId[i]] = msg.sender;
            s.tokenIdsByOwner[_tokenAddress][msg.sender].push(_tokenId[i]);
            s.ownerTokenIndexByTokenId[_tokenAddress][msg.sender][_tokenId[i]] = s.tokenIdsByOwner[_tokenAddress][msg.sender].length -1;
            
            //if a new user is depositing this gotchi OR if it's been more than a day (86,400 seconds) since the user withdrew, charge a fee
            //if the gotchi has never been deposited, the Gotchi struct will default to 0 values (e.g., address(0))
            if(s.gotchiMapping[_tokenId[i]].DepositorAddress != msg.sender || (block.timestamp - s.gotchiMapping[_tokenId[i]].timeCheckedOut) > 86400){
                waiveFee = false;
            }
            
            s.gotchiMapping[_tokenId[i]].DepositorAddress = msg.sender;
            s.gotchiMapping[_tokenId[i]].tokenId = _tokenId[i];
            s.gotchiMapping[_tokenId[i]].timeCheckedOut = 0;

            //deposit the ERC721
            IERC721(_tokenAddress).safeTransferFrom(msg.sender,address(this),_tokenId[i],"");

        }

        //charge the user a deposit fee
        if(!waiveFee && s.fee721 > 0){
            IERC20(im_ghstAddress).transferFrom(msg.sender, address(this), s.fee721);
            s.totalFeesCollected += s.fee721;

            //50% of the fee goes to the vGHST pool, 50% goes to the contract owner and creator
            IERC20(im_ghstAddress).transfer(s.contractOwner, s.fee721.mul(100).div(400));
            IERC20(im_ghstAddress).transfer(s.contractCreator, s.fee721.mul(100).div(400));
            IERC20(im_ghstAddress).transfer(s.vGHSTAddress, s.fee721.mul(200).div(400));
        }

        
    }

    function withdrawERC721(address _tokenAddress, uint256[] calldata _tokenId) public {

        require(_tokenId.length <= 10, "Fail: can only withdraw 10 gotchis at a time");
        uint256 totalGHSTEscrow;
        uint256 totalVGHSTEscrow;


        for(uint256 i = 0; i<_tokenId.length; i++){
            //only the original depositor can withdraw an ERC721 token
            require(s.deposits[_tokenAddress][_tokenId[i]] == msg.sender, "Only the owner can withdraw");

            //If the gotchi has any GHST or vGHST deposits, withdraw it and take a fee, and send to the user
            uint256 ghstBalance = IAavegotchi(im_diamondAddress).escrowBalance(_tokenId[i], im_ghstAddress);
            uint256 vghstBalance = IAavegotchi(im_diamondAddress).escrowBalance(_tokenId[i], s.vGHSTAddress);
            if(ghstBalance > 0){
                IAavegotchi(im_diamondAddress).transferEscrow(_tokenId[i], im_ghstAddress, address(this), ghstBalance);
                totalGHSTEscrow += ghstBalance;
            }
            if(vghstBalance > 0){
                IAavegotchi(im_diamondAddress).transferEscrow(_tokenId[i], s.vGHSTAddress, address(this), vghstBalance);
                totalVGHSTEscrow += vghstBalance;
            }
            
            //send the user back his ERC721
            IERC721(_tokenAddress).safeTransferFrom(address(this), msg.sender, _tokenId[i]);

            //reset our internal tracking of deposits -- address(0) is the default state for mapping addresses
            s.deposits[_tokenAddress][_tokenId[i]] = address(0);
            //remove this from the array of depositor tokens
            if(s.tokenIdsByOwner[_tokenAddress][msg.sender].length > 1){
                // Get the index of the token that has to be removed from the list
                // of tokens owned by the current owner.
                uint256 tokenIndexToDelete = s.ownerTokenIndexByTokenId[_tokenAddress][msg.sender][_tokenId[i]];

                // To keep the list of tokens without gaps, and thus reducing the
                // gas cost associated with interacting with the list, the last
                // token in the owner"s list of tokens is moved to fill the gap
                // created by removing the token.
                uint256 tokenIndexToMove = s.tokenIdsByOwner[_tokenAddress][msg.sender].length - 1;

                // Overwrite the token that is to be removed with the token that
                // was at the end of the list. It is possible that both are one and
                // the same, in which case nothing happens.
                s.tokenIdsByOwner[_tokenAddress][msg.sender][tokenIndexToDelete] =
                s.tokenIdsByOwner[_tokenAddress][msg.sender][tokenIndexToMove];
            }
            // Remove the last item in the list of tokens owned by the current
            // owner. This item has either already been copied to the location of
            // the token that is to be transferred, or is the only token of this
            // owner in which case the list of tokens owned by this owner is now
            // empty.
            s.tokenIdsByOwner[_tokenAddress][msg.sender].pop();

            s.gotchiMapping[_tokenId[i]].timeCheckedOut = block.timestamp;

        }

        //charge the user a withdrawal fee
        //IERC20(im_ghstAddress).transferFrom(msg.sender, address(this), s.fee721);
        //s.totalFeesCollected += s.fee721;
        if(totalGHSTEscrow > 0){sendERC20withFee(im_ghstAddress, totalGHSTEscrow, msg.sender);}
        if(totalVGHSTEscrow > 0){sendERC20withFee(s.vGHSTAddress, totalGHSTEscrow, msg.sender);}
    }

    

    //we allow users to directly enter GHST from their gotchis' pocket into the pool without directly receiving
    //the GHST to the user address
    function compoundEscrow(uint256 _tokenId) public whenNotPaused{
        //only the original depositor or the owner can compound the GHST
        require(s.deposits[im_diamondAddress][_tokenId] == msg.sender || msg.sender == s.contractOwner, "Only the owner can compound the escrow");

        //we get the amount of GHST in the escrow -- must be more than 0
        uint256 escrowBalance = IAavegotchi(im_diamondAddress).escrowBalance(_tokenId, im_ghstAddress);
        require(escrowBalance > 0, "Fail: this gotchi has no GHST in pocket");

        //transfer the escrow from the gotchi pocket to address(this)
        IAavegotchi(im_diamondAddress).transferEscrow(_tokenId, im_ghstAddress, address(this), escrowBalance);

        //mint the corresponding number of vGHST and send to the gotchi wallet
        uint256 vGHSTReturned = vGHST(s.vGHSTAddress).enter(escrowBalance);
        address escrowAddress = IAavegotchi(im_diamondAddress).gotchiEscrow(_tokenId);
        vGHST(s.vGHSTAddress).transfer(escrowAddress,vGHSTReturned);
    }

    //a helper function to send GHST to the external recipient, taking a designated fee first
    function sendERC20withFee(address _tokenAddress,uint256 _amount, address _recipient) internal{
        //we take a designated fee from the withdrawal
        //solidity doesn't allow floating point math, so we have to multiply up to take percentages
        //here, e.g., a fee of 50 basis points would be a 0.5% fee
        //half the fee goes to the protocol, 25% goes to the contract owner, 25% goes to the contract creator 
        //we send 25% each to the owner and creator, and the remaining 50% just stays in the contract
        uint256 feeAmount = _amount.mul(s.feeBP).div(10000);

        //50% of the fees collected go to the vGHST holders -- treat this differently if we're sending GHST or vGHST
        //if the token being sent is GHST, then just add the fee amount to the total and the 50% of the fees goes
        //directly to the vGHST contract
        if(_tokenAddress == im_ghstAddress){ 
            s.totalFeesCollected += feeAmount;
            IERC20(_tokenAddress).transfer(s.vGHSTAddress, feeAmount.mul(200).div(400));
        }
        //if it's vGHST, need to figure out how much GHST is being "collected", and need to burn that amount of vGHST
        else if(_tokenAddress == s.vGHSTAddress){
            uint256 ghstAmount = vGHST(s.vGHSTAddress).convertVGHST(feeAmount);
            s.totalFeesCollected += ghstAmount;

            //we burn the requisite amount of vGHST so that the remaining vGHST holders receive the underlying GHST
            vGHST(s.vGHSTAddress).burn(feeAmount.mul(200).div(400));

        }

        //25% of the fees go to the manager, 25% to the creator
        IERC20(_tokenAddress).transfer(s.contractOwner, feeAmount.mul(100).div(400));
        IERC20(_tokenAddress).transfer(s.contractCreator, feeAmount.mul(100).div(400));
        //we send the escrow - fee to the owner
        IERC20(_tokenAddress).transfer(_recipient, _amount.sub(feeAmount));
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //These are emergency admin functions helpful in the testing stage -- comment out later
    function ReturnERC1155(address _tokenAddress, uint256 _id, uint256 _value) public onlyOwner{
        IERC1155(_tokenAddress).safeTransferFrom(address(this),msg.sender,_id,_value,"");
    }

    function ReturnERC721(address _tokenAddress, uint256 _id) public onlyOwner{
        IERC721(_tokenAddress).safeTransferFrom(address(this),msg.sender,_id,"");
    }

    function ReturnERC20(address _tokenAddress) public onlyOwner{
        ERC20(_tokenAddress).transfer(msg.sender, ERC20(_tokenAddress).balanceOf(address(this)));
    }

    function doSomething(address _addr, bytes memory _msg) public onlyOwner{
        _addr.call(_msg);
    }

    //Everything below here is implementing interface-required functions
    /////////////////////////////////////////////////////////////////////////////////////


    function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {
        return s.supportedInterfaces[_interfaceId];
    }

    /////////////////////////////////////////////////////////////////////////////////////

    function creator() external view  returns (address) {
        return s.contractCreator;
    }

    function transferCreator(address _newContractCreator) external  {
        require(msg.sender == s.contractCreator, "Failed: Must be contract creator");
        s.contractCreator = _newContractCreator;
    }

    function owner() external view override returns (address) {
        return s.contractOwner;
    }

    function transferOwnership(address _newContractOwner) external override {
        address previousOwner = s.contractOwner;
        require(msg.sender == previousOwner, "Failed: Must be contract owner");
        s.contractOwner = _newContractOwner;
        emit OwnershipTransferred(previousOwner, _newContractOwner);
    }

    modifier onlyOwner{
         require(msg.sender == s.contractOwner,"Failed: not contract owner");
         _;
     }

    /////////////////////////////////////////////////////////////////////////////////////

     /**
        @notice Handle the receipt of a single ERC1155 token type.
        @dev An ERC1155-compliant smart contract MUST call this function on the token recipient contract, at the end of a `safeTransferFrom` after the balance has been updated.        
        This function MUST return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` (i.e. 0xf23a6e61) if it accepts the transfer.
        This function MUST revert if it rejects the transfer.
        Return of any other value than the prescribed keccak256 generated value MUST result in the transaction being reverted by the caller.
        @param _operator  The address which initiated the transfer (i.e. msg.sender)
        @param _from      The address which previously owned the token
        @param _id        The ID of the token being transferred
        @param _value     The amount of tokens being transferred
        @param _data      Additional data with no specified format
        @return           `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
    */
    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external view returns (bytes4) {
        _operator; // silence not used warning
        _from; // silence not used warning
        _id; // silence not used warning
        _value; // silence not used warning
        _data;
        return ERC1155_ACCEPTED;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4){
        operator;
        from;
        ids;
        values;
        data;
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }


    function onERC721Received(
        address, /* _operator */
        address, /*  _from */
        uint256, /*  _tokenId */
        bytes calldata /* _data */
    ) external pure  returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    /////////////////////////////////////////////////////////////////////////////////////



}