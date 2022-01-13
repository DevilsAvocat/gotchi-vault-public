//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
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

// All state variables are accessed through this struct
// To avoid name clashes and make clear a variable is a state variable
// state variable access starts with "s." which accesses variables in this struct
struct AppStorage {
    // IERC165
    mapping(bytes4 => bool) supportedInterfaces;
    address contractOwner;
    address contractCreator;

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

    //uint256 public totalFeesCollected;
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

contract GotchiManager is IERC173, Initializable, IERC721ReceiverUpgradeable, IERC1155ReceiverUpgradeable, ERC20Upgradeable {

    using SafeMath for uint256;

    // State variables are prefixed with s.
    AppStorage internal s;
    // Immutable values are prefixed with im_ to easily identify them in code
    // these are constant not immutable because this upgradeable contract doesn't have a constructor
    address internal constant im_diamondAddress = 0x86935F11C86623deC8a25696E1C19a8659CbF95d;
    address internal constant im_ghstAddress = 0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7;
    address internal constant im_realmAddress = 0x1D0360BaC7299C86Ec8E99d0c1C9A95FEfaF2a11;
    address internal constant im_raffleAddress = 0x6c723cac1E35FE29a175b287AE242d424c52c1CE;
    address internal constant im_stakingAddress = 0xA02d547512Bb90002807499F05495Fe9C4C3943f;

    bytes4 internal constant ERC1155_ACCEPTED = 0xf23a6e61; // Return value from `onERC1155Received` call if a contract accepts receipt (i.e `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`).
    uint256 internal constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    

    function initialize(
        string memory name, 
        string memory symbol,
        address _contractOwner,
        uint256 _feeBP,
        uint256 _fee721
        ) public initializer{

        __ERC20_init(name, symbol);
        s.contractOwner = _contractOwner;
        s.contractCreator = _contractOwner;
        s.feeBP = _feeBP;
        s.fee721 = _fee721;


        IAavegotchi(im_diamondAddress).setApprovalForAll(im_diamondAddress, true);
        StakingContract(im_stakingAddress).setApprovalForAll(im_raffleAddress, true);
        IERC20(im_ghstAddress).approve(im_stakingAddress, MAX_INT);
    }

    function getTokenIdsOfDepositor(address _depositor,address _tokenAddress) public view returns(uint256[] memory){
        return s.tokenIdsByOwner[_tokenAddress][_depositor];
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

    function setApprovals() public onlyOwner{
        IAavegotchi(im_diamondAddress).setApprovalForAll(im_diamondAddress, true);
        StakingContract(im_stakingAddress).setApprovalForAll(im_raffleAddress, true);
        IERC20(im_ghstAddress).approve(im_stakingAddress, MAX_INT);
        IERC20(im_ghstAddress).approve(address(this), MAX_INT);

    }

    /////////////////////////////////////////////////////////////////////////////////////
    //In this section, we have wrapper functions that can be called by the owner, to stake and 
    //unstake GHST, claim raffle tickets, enter raffle tickets into raffles, sell ERC1155 items on baazaar
    
    /////////////////////////////////////////////////////////////////////////////////////
    //Wrapper functions for the staking diamond contract
    function frens() public view returns (uint256 frens_) {
        frens_ = StakingContract(im_stakingAddress).frens(address(this));
    }

    function stakeIntoPool(address _poolContractAddress, uint256 _amount) public onlyOwner{
        StakingContract(im_stakingAddress).stakeIntoPool(_poolContractAddress, _amount);
    }

    function withdrawFromPool(address _poolContractAddress, uint256 _amount) public onlyOwner{
        StakingContract(im_stakingAddress).withdrawFromPool(_poolContractAddress, _amount);
    }

    function claimTickets(uint256[] calldata _ids, uint256[] calldata _values) public onlyOwner{
        StakingContract(im_stakingAddress).claimTickets(_ids, _values);
    }

    function convertTickets(uint256[] calldata _ids, uint256[] calldata _values) public onlyOwner{
        StakingContract(im_stakingAddress).convertTickets(_ids, _values);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //Wrapper functions for the raffle contract
    function enterTickets(uint256 _raffleId, TicketItemIO[] calldata _ticketItems) public onlyOwner{
        RaffleContract(im_raffleAddress).enterTickets(_raffleId, _ticketItems);
    }

    function claimPrize(
        uint256 _raffleId,
        address _entrant,
        ticketWinIO[] calldata _wins
    ) public onlyOwner{
        RaffleContract(im_raffleAddress).claimPrize(_raffleId, _entrant, _wins);
    }

    //will need to update this to convert vouchers once the new raffle contract comes out

    /////////////////////////////////////////////////////////////////////////////////////
    //Wrapper functions for the baazaar
    //We allow the owner to list items UNLESS they belong to a depositor -- so basically the owner
    //can list on the baazaar raffle tickets and raffle winnings
    function setERC1155Listing(address _erc1155TokenAddress, uint256 _erc1155TypeId, uint256 _quantity, uint256 _priceInWei) public onlyOwner{
        IAavegotchi(im_diamondAddress).setERC1155Listing(_erc1155TokenAddress, _erc1155TypeId, _quantity, _priceInWei);
    }
    
    function cancelERC1155Listing(uint256 _listingId) public onlyOwner{
        IAavegotchi(im_diamondAddress).cancelERC1155Listing(_listingId);
    }

    function addERC721Listing(address _erc721TokenAddress,uint256 _erc721TokenId,uint256 _priceInWei) public onlyOwner{
        require(s.deposits[_erc721TokenAddress][_erc721TokenId] == address(0), "cannot call this function for a depositor's item");
        IAavegotchi(im_diamondAddress).addERC721Listing(_erc721TokenAddress, _erc721TokenId, _priceInWei);
    }

    function cancelERC721ListingByToken(address _erc721TokenAddress, uint256 _erc721TokenId) public onlyOwner{
        require(s.deposits[_erc721TokenAddress][_erc721TokenId] == address(0), "cannot call this function for a depositor's item");
        IAavegotchi(im_diamondAddress).cancelERC721ListingByToken(_erc721TokenAddress, _erc721TokenId);
    }

    function updateERC721Listing(address _erc721TokenAddress,uint256 _erc721TokenId,address _owner) public onlyOwner{
        require(s.deposits[_erc721TokenAddress][_erc721TokenId] == address(0), "cannot call this function for a depositor's item");
        IAavegotchi(im_diamondAddress).updateERC721Listing(_erc721TokenAddress, _erc721TokenId, _owner);
    }

    
    /////////////////////////////////////////////////////////////////////////////////////
    //Allow users to withdraw the escrow from their gotchi
    function transferEscrow(uint256 _tokenId, address _erc20Contract, address _recipient, uint256 _transferAmount) public{
        require(s.deposits[im_diamondAddress][_tokenId] == msg.sender, "Only owner can withdraw escrow!");
        if(_erc20Contract == im_ghstAddress){
            IAavegotchi(im_diamondAddress).transferEscrow(_tokenId, _erc20Contract, address(this), _transferAmount);
            sendGHSTwithFee(_transferAmount, _recipient);
        }
        else{
            IAavegotchi(im_diamondAddress).transferEscrow(_tokenId, _erc20Contract, _recipient, _transferAmount);
        }

    }

    /////////////////////////////////////////////////////////////////////////////////////
    //Misc. wrapper functions -- interact, spend skill points
    function interact(uint256[] calldata _tokenIds) public{
        IAavegotchi(im_diamondAddress).interact(_tokenIds);
    }

    function spendSkillPoints(uint256 _tokenId, int16[4] calldata _values) public{

        require(s.deposits[im_diamondAddress][_tokenId] == msg.sender, "Only owner can call!");

        IAavegotchi(im_diamondAddress).spendSkillPoints(_tokenId, _values);
    }


    /////////////////////////////////////////////////////////////////////////////////////
    //In this section, we allow users to deposit and withdraw their ERC721 tokens
    //todo: only charge on first deposit of a gotchi?
    function depositERC721(address _tokenAddress, uint256[] calldata _tokenId) public {
        require(_tokenId.length <= 10, "Fail: can only submit 10 gotchis at a time");

        //bool waiveFee = true;

        for(uint256 i = 0; i<_tokenId.length; i++){

            //we track that this user deposited this specific ERC721 token
            s.deposits[_tokenAddress][_tokenId[i]] = msg.sender;
            s.tokenIdsByOwner[_tokenAddress][msg.sender].push(_tokenId[i]);
            s.ownerTokenIndexByTokenId[_tokenAddress][msg.sender][_tokenId[i]] = s.tokenIdsByOwner[_tokenAddress][msg.sender].length -1;

            //deposit the ERC721
            IERC721(_tokenAddress).safeTransferFrom(msg.sender,address(this),_tokenId[i],"");

            //if( now - time deposited > checkoutperiod){waiveFee = false}
        }

        //charge the user a deposit fee
        //if(!waiveFee)
        IERC20(im_ghstAddress).transferFrom(msg.sender, address(this), s.fee721);
        //todo: send fees to managers and creator
        
    }

    function withdrawERC721(address _tokenAddress, uint256[] calldata _tokenId) public {

        require(_tokenId.length <= 10, "Fail: can only withdraw 10 gotchis at a time");
        uint256 totalEscrow;

        for(uint256 i = 0; i<_tokenId.length; i++){
            //only the original depositor can withdraw an ERC721 token
            require(s.deposits[_tokenAddress][_tokenId[i]] == msg.sender, "Only the owner can withdraw");

            //If the gotchi has any GHST deposits, withdraw it and take a fee, and send to the user
            //todo: change this to vGHST?
            uint256 escrowBalance = IAavegotchi(im_diamondAddress).escrowBalance(_tokenId[i], im_ghstAddress);
            if(escrowBalance > 0){
                IAavegotchi(im_diamondAddress).transferEscrow(_tokenId[i], im_ghstAddress, address(this), escrowBalance);
                totalEscrow += escrowBalance;
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
        }

        //charge the user a withdrawal fee
        IERC20(im_ghstAddress).transferFrom(msg.sender, address(this), s.fee721);
        sendGHSTwithFee(totalEscrow, msg.sender);

    }

    /////////////////////////////////////////////////////////////////////////////////////
    //In this section, we pull from Qidao's camToken implementation to allow users to own
    //a fraction of the deposited pot, which can be compounded

    // Locks ghst and mints our vGHST (shares)
    function enter(uint256 _amount) public returns(uint256) {
        
        //the total "pool" of GHST held is a combination of the GHST directly held, and the GHST staked
        uint256 totalTokenLocked = totalGHST(address(this));

        uint256 totalShares = totalSupply(); // Gets the amount of vGHST in existence

        // Lock the Token in the contract
       
        IERC20(im_ghstAddress).transferFrom(msg.sender, address(this), _amount);
        
        if (totalShares == 0 || totalTokenLocked == 0) { // If no vGHST exists, mint it 1:1 to the amount put in
                _mint(msg.sender, _amount);
                return _amount;
        } else {
            uint256 vGHSTAmount = _amount.mul(totalShares).div(totalTokenLocked);
            _mint(msg.sender, vGHSTAmount);
            return vGHSTAmount;
        }
    }

    //a function to get the total GHST held by an address between the wallet AND staked
    function totalGHST(address _user) public view returns(uint256 _totalGHST){
        //get the total amount of GHST held directly in the wallet
        uint256 totalGHSTHeld = IERC20(im_ghstAddress).balanceOf(_user);
        //find the total amount of GHST this contract has staked
        uint256 totalGHSTStaked = 0;

        PoolStakedOutput[] memory poolsStaked = StakingContract(im_stakingAddress).stakedInCurrentEpoch(_user);
        for(uint256 i = 0; i < poolsStaked.length; i++){
            if(poolsStaked[i].poolAddress == im_ghstAddress){
                totalGHSTStaked = poolsStaked[i].amount;
                break;
            }

        }

        _totalGHST = totalGHSTHeld + totalGHSTStaked;
    }

    function convertVGHST(uint256 _share) public view returns(uint256 _ghst){
        if(_share > 0){
            uint256 totalShares = totalSupply(); // Gets the amount of vGHST in existence

            //get the total amount of GHST held by the contract
            uint256 totalTokenLocked = totalGHST(address(this));

            //calculate how much of our total pool this share owns
            _ghst = _share.mul(totalTokenLocked).div(totalShares);
        }
        else return 0;
            
    }

    // claim ghst by burning vGHST
    function leave(uint256 _share) public {
        if(_share>0){

            uint256 ghstAmount = convertVGHST(_share);

            //if balanceof this < ghst Amount, unstake ghstAmount
            if(ghstAmount > IERC20(im_ghstAddress).balanceOf(address(this))){
                StakingContract(im_stakingAddress).withdrawFromPool(im_ghstAddress, ghstAmount);
            }
            _burn(msg.sender, _share);
            
            // Now we withdraw the GHST from the vGHST Pool (this contract) and send to user as GHST.
            //IERC20(usdc).safeApprove(address(this), amTokenAmount);
            sendGHSTwithFee(ghstAmount, msg.sender);
        }
    }

    //we allow users to directly enter GHST from their gotchis' pocket into the pool without directly receiving
    //the GHST to the user address
    function compoundEscrow(uint256 _tokenId) public {
        //only the original depositor can compound the GHST
        require(s.deposits[im_diamondAddress][_tokenId] == msg.sender, "Only the owner can compound the escrow");

        //we get the amount of GHST in the escrow -- must be more than 0
        uint256 escrowBalance = IAavegotchi(im_diamondAddress).escrowBalance(_tokenId, im_ghstAddress);
        require(escrowBalance > 0, "Fail: this gotchi has no GHST in pocket");
        
        //transfer the escrow from the gotchi pocket to address(this)
        IAavegotchi(im_diamondAddress).transferEscrow(_tokenId, im_ghstAddress, address(this), escrowBalance);

        //mint the corresponding number of vGHST directly to the gotchi wallet       
        uint256 totalTokenLocked = IERC20(im_ghstAddress).balanceOf(address(this));
        uint256 totalShares = totalSupply(); // Gets the amount of vGHST in existence
        uint256 vGHSTAmount = escrowBalance.mul(totalShares).div(totalTokenLocked);
        address escrowAddress = IAavegotchi(im_diamondAddress).gotchiEscrow(_tokenId);
        _mint(escrowAddress, vGHSTAmount);
    }

    //a helper function to send GHST to the external recipient, taking a designated fee first
    function sendGHSTwithFee(uint256 _amount, address _recipient) internal{
        //we take a designated fee from the withdrawal
        //solidity doesn't allow floating point math, so we have to multiply up to take percentages
        //here, e.g., a fee of 50 basis points would be a 0.5% fee
        //half the fee goes to the protocol, 25% goes to the contract owner, 25% goes to the contract creator 
        //we send 25% each to the owner and creator, and the remaining 50% just stays in the contract
        uint256 feeAmount = _amount.mul(s.feeBP).div(10000);
        IERC20(im_ghstAddress).transferFrom(address(this), s.contractOwner, feeAmount.mul(100).div(400));
        IERC20(im_ghstAddress).transferFrom(address(this), s.contractCreator, feeAmount.mul(100).div(400));
        //we send the escrow - fee to the owner
        IERC20(im_ghstAddress).transferFrom(address(this), _recipient, _amount.sub(feeAmount));
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