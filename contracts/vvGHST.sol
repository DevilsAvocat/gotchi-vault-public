// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.0 (token/ERC20/extensions/ERC20Snapshot.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ArraysUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./interfaces/QiVault.sol";
import "./interfaces/Balancer.sol";

import "./vGHST.sol";

import "./vQi.sol";


/**
 * @dev This contract extends an ERC20 token with a snapshot mechanism. When a snapshot is created, the balances and
 * total supply at the time are recorded for later access.
 *
 * This can be used to safely create mechanisms based on token balances such as trustless dividends or weighted voting.
 * In naive implementations it's possible to perform a "double spend" attack by reusing the same balance from different
 * accounts. By using snapshots to calculate dividends or voting power, those attacks no longer apply. It can also be
 * used to create an efficient ERC20 forking mechanism.
 *
 * Snapshots are created by the internal {_snapshot} function, which will emit the {Snapshot} event and return a
 * snapshot id. To get the total supply at the time of a snapshot, call the function {totalSupplyAt} with the snapshot
 * id. To get the balance of an account at the time of a snapshot, call the {balanceOfAt} function with the snapshot id
 * and the account address.
 *
 * NOTE: Snapshot policy can be customized by overriding the {_getCurrentSnapshotId} method. For example, having it
 * return `block.number` will trigger the creation of snapshot at the begining of each new block. When overridding this
 * function, be careful about the monotonicity of its result. Non-monotonic snapshot ids will break the contract.
 *
 * Implementing snapshots for every block using this method will incur significant gas costs. For a gas-efficient
 * alternative consider {ERC20Votes}.
 *
 * ==== Gas Costs
 *
 * Snapshots are efficient. Snapshot creation is _O(1)_. Retrieval of balances or total supply from a snapshot is _O(log
 * n)_ in the number of snapshots that have been created, although _n_ for a specific account will generally be much
 * smaller since identical balances in subsequent snapshots are stored as a single entry.
 *
 * There is a constant overhead for normal ERC20 transfers due to the additional snapshot bookkeeping. This overhead is
 * only significant for the first transfer that immediately follows a snapshot for a particular account. Subsequent
 * transfers will have normal cost until the next snapshot, and so on.
 */

// All state variables are accessed through this struct
// To avoid name clashes and make clear a variable is a state variable
// state variable access starts with "s." which accesses variables in this struct
struct AppStorage {
    //we use 3 internal snapshots to track Qi a user is entitled to:
    //we track user balances of vvGHST, taking a snapshot at the end of every week
    mapping(address => Snapshots) accountBalanceSnapshots;
    //at same time, we take a snapshot of the total supply of vvGHST
    Snapshots totalSupplySnapshots;
    //finally, every week once the Qi rewards are airdropped, we add the balance of the Qi rewarded that week
    uint256[] qiAirdrops;
    //putting all this together, for any snapshot, the user will be entitled to: (his balance / the total supply) * QiReward 
    //we track how much vQi he's received in case he withdrew some already
    mapping(address => uint256) vQiClaimed;

    // Snapshot ids increase monotonically, with the first value being 1. An id of 0 is invalid.
    CountersUpgradeable.Counter currentSnapshotId;

    //various permissions
    address owner;
    address contractCreator;
    mapping(address => bool) approvedUsers;

    //the Qidao vGHST vault address
    address vaultAddress;
    uint256 vaultID;

    //tracking fees collected
    uint256 totalFeesCollected;
    uint256 withdrawalFeeBP;

    //our target collateral-debt-ratios
    uint256 targetCDRHigh;
    uint256 targetCDRLow;

    //Balancer pool information
    bytes32 poolId;
    IAsset[] assets;
    address BPSP;

    uint256 profitFee;

    uint256 supplyCap;
}

// Snapshotted values have arrays of ids and the value corresponding to that id. These could be an array of a
// Snapshot struct, but that would impede usage of functions that work on an array.
struct Snapshots {
    uint256[] ids;
    uint256[] values;
}

contract vvGHST is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    using ArraysUpgradeable for uint256[];
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Immutable values are prefixed with im_ to easily identify them in code
    // these are constant not immutable because this upgradeable contract doesn't have a constructor
    // (immutable variables must be declared in the constructor -- i like the im prefix though)
    address internal constant im_vGHST = 0x51195e21BDaE8722B29919db56d95Ef51FaecA6C;
    address internal constant im_vQi = 0xB424dfDf817FaF38FF7acF6F2eFd2f2a843d1ACA;
    address internal constant im_Qi = 0x580A84C73811E1839F75d86d75d88cCa0c241fF4;
    address internal constant im_balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant im_bal = 0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3;
    address internal constant im_merkle = 0x0F3e0c4218b7b0108a3643cFe9D3ec0d4F57c54e;
    address internal constant im_mai = 0xa3Fa99A148fA48D14Ed51d610c367C61876997F1;
    address internal constant im_ghst = 0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7;
    address internal constant im_qs = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    address internal constant im_usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;


    uint256 constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    // State variables are prefixed with s.
    AppStorage internal s;

    function initialize(
        address _owner,
        string memory name, 
        string memory symbol,
        address vaultAddress,
        uint256 targetCDRHigh,
        uint256 targetCDRLow,
        uint256 _withdrawlFeeBP,
        uint256 _profitFee
        ) public initializer{

        __ERC20_init(name, symbol);

        s.owner = _owner;
        s.contractCreator = _owner;

        //this is the QiDao vault contract address
        s.vaultAddress = vaultAddress;

        //we create a new vault and store the vault number
        s.vaultID = QiVault(vaultAddress).createVault();

        s.targetCDRHigh = targetCDRHigh;
        s.targetCDRLow = targetCDRLow;

        s.withdrawalFeeBP = _withdrawlFeeBP;
        s.profitFee = _profitFee;

        s.poolId = 0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012;

        s.BPSP = 0x06Df3b2bbB68adc8B0e302443692037ED9f91b42;

        s.assets = [
            IAsset(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174), //usdc
            IAsset(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063), //Dai
            IAsset(0xa3Fa99A148fA48D14Ed51d610c367C61876997F1), //mimatic
            IAsset(0xc2132D05D31c914a87C6611C10748AEb04B58e8F) //usdt
        ];

        //push one element so that qiAirdrops index matches the snapshotId counter (which starts at 1)
        s.qiAirdrops.push(0);

        setApprovalsInternal();
    }

    function setApprovalsInternal() internal {
        //approve vQi to take Qi
        IERC20Upgradeable(im_Qi).approve(im_vQi, MAX_INT);

        //approve qidao vault to take vGHST
        IERC20Upgradeable(im_vGHST).approve(s.vaultAddress, MAX_INT);

        //approve qidao vault to take mai
        IERC20Upgradeable(im_mai).approve(s.vaultAddress, MAX_INT);

        //approve balancer to take Mai
        IERC20Upgradeable(im_mai).approve(im_balancer, MAX_INT);

        //approve balancer to take BPSP
        IERC20Upgradeable(s.BPSP).approve(im_balancer,MAX_INT);

        //approve balancer to take Bal
        IERC20Upgradeable(im_bal).approve(im_balancer, MAX_INT);

        //approve quickswap to take USDC
        IERC20Upgradeable(im_usdc).approve(im_qs, MAX_INT);

        //approve vGHST to take GHST
        IERC20Upgradeable(im_ghst).approve(im_vGHST, MAX_INT);
    }

    function setApprovals() public onlyOwner{
        setApprovalsInternal();
    }

    modifier onlyOwner() {
        require(msg.sender ==  s.owner, "onlyOwner: not allowed");
        _;
    }

    function getOwner() public view returns(address){
        return s.owner;
    }

    modifier onlyApproved() {
        require(msg.sender ==  s.owner || s.approvedUsers[msg.sender], "onlyApproved: not allowed");
        _;
    }

    function setApproved(address _user, bool _approval) public onlyOwner{
            s.approvedUsers[_user] = _approval;
        }
    
    function pause(bool _setPause) public onlyOwner{
        if(_setPause){_pause();}
        else _unpause();
    }

    function updateOwner(address _owner) public onlyOwner {
        s.owner = _owner;
    }

    function updateCreator(address _creator) public {
        require(msg.sender == s.contractCreator,"Can only be called by creator");
        s.contractCreator = _creator;
    }

    function joinPoolController(uint256 _mai) public onlyApproved{
        joinPool(_mai);
    }

    function joinPool(uint256 _mai) internal{

        uint256[] memory amountsIn = new uint256[](4);
        amountsIn[2] = _mai;

        bytes memory userDataEncoded = abi.encode(1,amountsIn,0);

        JoinPoolRequest memory request;
        request.assets = s.assets;
        request.maxAmountsIn = amountsIn;
        request.userData = userDataEncoded;
        request.fromInternalBalance = false;

        Balancer(im_balancer).joinPool(s.poolId, address(this), address(this), request);
    }

    function leavePoolExactAmount(uint256 _mai) internal {
        uint256[] memory amountsOut = new uint256[](4);   
        amountsOut[2] = _mai;
     
        //BPT_IN_FOR_EXACT_TOKENS_OUT
        bytes memory userDataEncoded = abi.encode(2,amountsOut,IERC20Upgradeable(s.BPSP).balanceOf(address(this)));

        ExitPoolRequest memory request;
        request.assets = s.assets;
        request.minAmountsOut = amountsOut;
        request.userData = userDataEncoded;
        request.toInternalBalance = false;

        Balancer(im_balancer).exitPool(s.poolId,address(this),payable(address(this)),request);
  
    }


    function enter(uint256 _amount) public whenNotPaused returns(uint256){

        IERC20Upgradeable vGHST = IERC20Upgradeable(im_vGHST);

        //user can't mint more vvGHST than he has vGHST
        require(vGHST.balanceOf(msg.sender) >= _amount, "enter: insufficient vGHST balance to deposit");
        //must have approved the vQi contract to take Qi
        require(vGHST.allowance(msg.sender, address(this)) >= _amount, "enter: must approve vvGHST contract to withdraw vGHST");
        //there must be available Mai to borrow for vGHST from Qidao
        //require(IERC20Upgradeable(im_mai).balanceOf(s.vaultAddress) > 0,"enter: insufficient Mai debt limit");

        //get total vGHST in the vGHST vault
        uint256 totalTokenLocked = totalvGHST();

        uint256 totalShares = totalSupply(); // Gets the amount of vvGHST in existence
        uint256 vvGHSTAmount = convertToShares(_amount);

        uint256 debtRemaining = IERC20Upgradeable(im_mai).balanceOf(s.vaultAddress);

        //can only proceed if there's debt left to borrow OR we've allowed users to front vGHST
        require(debtRemaining > 0 || s.supplyCap > totalShares,"Insufficient debt ceiling or supply cap");

        //if there's no debt but we have allowed for additional vvGHST to be minted in excess of Mai debt...
        //Note: if debt == 0, we know that supplyCap must be greater than totalShares because of the last require
        if(debtRemaining == 0){
            //check that there's enough supply left for the user
            if(s.supplyCap - totalShares < vvGHSTAmount){
                vvGHSTAmount = s.supplyCap - totalShares;
            }
        }

        // transfer the vGHST to the contract
        vGHST.transferFrom(msg.sender, address(this), _amount);


        //deposit vGHST into the QiDao vault
        QiVault(s.vaultAddress).depositCollateral(s.vaultID, _amount);

        //rebalance vault if there's debt left to borrow
        if(debtRemaining > 0){
            _rebalanceVault();
        }

        _mint(msg.sender, vvGHSTAmount);
        return vvGHSTAmount;
    
    }

    function convertToShares(uint256 _assets) public view returns(uint256 shares){
        //get total vGHST in the vGHST vault
        uint256 totalTokenLocked = totalvGHST();
        uint256 totalShares = totalSupply(); // Gets the amount of vvGHST in existence

        if (totalShares == 0 || totalTokenLocked == 0){
            return _assets;
        }
        return _assets.mul(totalShares).div(totalTokenLocked);
    }

    // claim vGhst by burning vvGHST -- this function is largely from QiDao code
    // we charge a fee on withdrawal
    function leave(uint256 _share) public {
        if(_share>0){
            require(balanceOf(msg.sender) >= _share,"insufficient balance of vvGHST");
            //the amount of vGHST the user is owed
            uint256 vghstAmount = convertToAssets(_share);

            //check whether withdrawing this will put under CDR limit
            uint256 newBalance = QiVault(s.vaultAddress).vaultCollateral(s.vaultID).sub(vghstAmount);
            uint256 vaultDebt = QiVault(s.vaultAddress).vaultDebt(s.vaultID);
            uint256 debtValue = vaultDebt.mul(QiVault(s.vaultAddress).getTokenPriceSource());
            
            uint256 newCollateralValueTimes100 = (newBalance*QiVault(s.vaultAddress).getEthPriceSource())*100;

            uint256 newCDR;

            if(debtValue != 0){
                newCDR = newCollateralValueTimes100.div(debtValue);
            }

            //if this withdrawal puts us below our minimum CDR, unwind some of the strategy
            if(debtValue == 0 || newCDR < s.targetCDRHigh){

                //100000000 is the "getTokenPriceSource" from Mai's vaults
                uint256 targetDebt = newCollateralValueTimes100/(s.targetCDRHigh*100000000);

                uint256 maiToPayBack = vaultDebt.sub(targetDebt);

                //withdraw maiToPayBack from Balancer
                leavePoolExactAmount(maiToPayBack);

                //repay the debt -- this will charge 0.5%.  
                QiVault(s.vaultAddress).payBackToken(s.vaultID, maiToPayBack);
            }

            uint256 vQiToClaim = vQiClaimable(msg.sender);

            //if the user is only burning some of their vvGHST, give them a proportional amount of the vQi they've earned
            if(_share < balanceOf(msg.sender)){
                vQiToClaim = (_share.mul(vQiToClaim)).div(balanceOf(msg.sender));  
            }

            s.vQiClaimed[msg.sender] += vQiToClaim;

            //burn the user's vvGHST token
            _burn(msg.sender, _share);
            
            // Now we withdraw the vGHST from the vvGHST Pool (this contract) and send to user as vGHST.
            //we take a designated fee from the withdrawal
            //solidity doesn't allow floating point math, so we have to multiply up to take percentages
            //here, e.g., a fee of 50 basis points would be a 0.5% fee
            //half the fee goes to the protocol, 25% goes to the contract owner, 25% goes to the contract creator 
            //we send 25% each to the owner and creator, and the remaining 50% just stays in the contract
            uint256 vghst_feeAmount = vghstAmount.mul(s.withdrawalFeeBP).div(10000); 

            s.totalFeesCollected += vGHST(im_vGHST).convertVGHST(vghst_feeAmount);

            //withdraw vGHST to the contract EXCLUDING half the withdraw fee to cover the 0.5% repayment fee
            //this has the effect of aggressively covering the repayment fee, meaning remaining holders earn some
            //of the withdrawal fee too
            QiVault(s.vaultAddress).withdrawCollateral(s.vaultID, vghstAmount.sub(vghst_feeAmount));

            //we send the withdrawal amount - fee to the owner
            IERC20Upgradeable(im_vGHST).transfer(msg.sender, vghstAmount.sub(vghst_feeAmount));

            IERC20Upgradeable(im_vQi).transfer(msg.sender, vQiToClaim);

        }
    }

    function setCDR(uint256 _CDRHigh, uint256 _CDRLow) public onlyOwner{
        s.targetCDRHigh = _CDRHigh;
        s.targetCDRLow = _CDRLow;
    }

    function setSupplyCap(uint256 _cap) public onlyOwner{
        s.supplyCap = _cap;
    }
    
    function getSupplyCap() public view returns(uint256){
        return s.supplyCap;
    }

    //returns the CDR high or low targets depending on bool high
    function getCDRTarget(bool high) public view returns(uint256){
        if(high){
            return s.targetCDRHigh;
        }
        else{
            return s.targetCDRLow;
        }
    }

    function getCDR() public view returns(uint256){
        return QiVault(s.vaultAddress).checkCollateralPercentage(s.vaultID);
    }

    function getVaultID() public view returns(uint256){
        return s.vaultID;
    }

    function rebalanceVault() public onlyApproved{
        _rebalanceVault();
    }
    
    //this function rebalances the vault to within our target parameters
    //it takes on more debt as needed if health is high, and repays debt if health is weak
    function _rebalanceVault() internal {

        uint256 vaultBalance = QiVault(s.vaultAddress).vaultCollateral(s.vaultID);
        uint256 vaultDebt = QiVault(s.vaultAddress).vaultDebt(s.vaultID);

        uint256 debtValue = vaultDebt.mul(QiVault(s.vaultAddress).getTokenPriceSource());

        uint256 collateralValueTimes100 = (vaultBalance*QiVault(s.vaultAddress).getEthPriceSource())*100;

        uint256 CDR;
        if(debtValue != 0){
            CDR = collateralValueTimes100.div(debtValue);
        }
        
        //if CDR > target, that means we can afford to take out more debt
        if(debtValue == 0 || CDR > s.targetCDRHigh){
            //Collateral-debt-ratio = collateral / debt
            //so, debt = collateral / CDR
            uint256 targetDebt = collateralValueTimes100 / (s.targetCDRHigh * 100000000);

            //calculate amount of additional debt needed and borrow
            uint256 newDebt = targetDebt - vaultDebt;

            uint256 debtAvailable = IERC20Upgradeable(im_mai).balanceOf(s.vaultAddress);

            if(debtAvailable < newDebt){
                QiVault(s.vaultAddress).borrowToken(s.vaultID,debtAvailable);
                //deposit new debt (Mai) into Balancer
                joinPool(debtAvailable);
            }
            else{
                QiVault(s.vaultAddress).borrowToken(s.vaultID,newDebt);
                //deposit new debt (Mai) into Balancer
                joinPool(newDebt);
            }

            
        }

        //if CDR < target, that means we must repay some debt
        //we repay enough to get back to the high debt range
        else if(CDR < s.targetCDRLow){
            //Collateral-debt-ratio = collateral / debt
            //so, debt = collateral / CDR
            uint256 targetDebt = collateralValueTimes100 / (s.targetCDRHigh * 100000000);
            //since CDR is low, the current debt is higher than the target; need to figure out how much
            uint256 repayDebt = vaultDebt - targetDebt;

            //unstake from Qi pool
            leavePoolExactAmount(repayDebt);

            //repay the debt
            QiVault(s.vaultAddress).payBackToken(s.vaultID,repayDebt);
        }
    }

    //a function to get the total vGHST held
    function totalvGHST() public view returns(uint256 _totalvGHST){
        
        //check the balance of the Qidao vault
        _totalvGHST = QiVault(s.vaultAddress).vaultCollateral(s.vaultID);
    }

    //view function that returns the amount of vGHST a share of vvGHST represents
    function convertToAssets(uint256 _shares) public view returns(uint256 _assets){
        if(_shares > 0){
            uint256 totalShares = totalSupply(); // Gets the amount of vvGHST in existence

            //get the total amount of vGHST held by the contract
            uint256 totalTokenLocked = totalvGHST();

            //calculate how much of our total pool this share owns
            _assets = _shares.mul(totalTokenLocked).div(totalShares);
        }
        else{_assets = 0;}       
    }

    function updateWithdrawalFee(uint16 _withdrawalFee) public onlyOwner{
        s.withdrawalFeeBP=_withdrawalFee;
    }

    function updateProfitFee(uint16 _profitFee) public onlyOwner{
        s.profitFee=_profitFee;
    }

    function getWithdrawalFee() public view returns(uint256){
        return s.withdrawalFeeBP;
    }

    function getProfitFee() public view returns(uint256){
        return s.profitFee;
    }

    //returns the total fees collected in GHST
    function getTotalFees() public view returns(uint256){
        return s.totalFeesCollected;
    }

    function compoundQi() public onlyApproved{
        //get the balance of Qi in this contract
        uint256 balanceQi = IERC20Upgradeable(im_Qi).balanceOf(address(this));

        //enter that Qi into vQi contract, get back vQi
        vQi(im_vQi).enter(balanceQi);
    }

    //this function is called by the owner each week to pay the vvGHST contract its vQi airdrops
    function depositAirdropQi(uint256 _amount) public onlyOwner{

        //we pull the appropriate amount of Qi from the sender
        IERC20Upgradeable(im_Qi).transferFrom(s.owner, address(this), _amount);

        //we note how much qi was airdropped
        s.qiAirdrops.push(_amount);

        //compound qi into vqi
        compoundQi();
    }

    //this function is called by our approved bot when the contract receives Qi airdrop
    function receivedAirdrop() public onlyApproved{

        //check how much Qi we've received
        uint256 QiBalance = IERC20Upgradeable(im_Qi).balanceOf(address(this));
        require(QiBalance > 0, "qiAirdrop: there is no Qi to stake in this wallet");

        //calculate the profit fee 
        uint256 qi_feeAmount = QiBalance.mul(s.profitFee).div(10000); 
    
        //snapshot the amount of the airdrop and balances of vvGHST
        s.qiAirdrops.push(QiBalance.sub(qi_feeAmount));
        //_snapshot();

        //send out the profit fees to the owner and creators
        IERC20Upgradeable(im_Qi).transfer(s.owner, qi_feeAmount.mul(200).div(400));
        IERC20Upgradeable(im_Qi).transfer(s.contractCreator, qi_feeAmount.mul(200).div(400));
        
        //compound remaining Qi into vQi
        compoundQi();

    }

    //this function calculates how much vQi a user is eligible to claim from the contract
    //using snapshots, we track the percentage of the total vvGHST a user has when the Qidao
    //airdrop is received, the total supply, and the size of the airdrop.  By going through all
    //the snapshots, we can calculate the user's "life" entitlement across all airdrops.  We 
    //track how much a user has already claimed, to determine what he's still owed
    function vQiClaimable(address _user) public view returns(uint256 totalQi) {

        //go through each snapshot, which represents a single week.  
        //each snapshot corresponds to 3 different airdrops (Balancer, lending rewards, eQi)
        for(uint256 i = 1; i < s.currentSnapshotId.current(); i++){
            //calculate the user's balance of vvGHST at that snapshot...
            uint256 userBalance = balanceOfAt(_user,i);
            //the total supply of vvGHST...
            uint256 totalSupply = totalSupplyAt(i);
                
            uint256 airdrop = s.qiAirdrops[i];

            totalQi += (userBalance*airdrop)/totalSupply;
        }

        //we discount any Qi the user has already claimed
        totalQi -= s.vQiClaimed[_user];
    }

    //this function claims weekly rewards from the Balancer Merkle Orchard and compounds them;
    //data (merkleproof) for claim must be calculated offchain, can do so easily using Balancer UI and Frame to spoof vvGHST;
    //we receive Bal and Qi from the Merkle.  We compound the Qi into vQi, and sell the Bal for more vGHST;
    //profit fee is taken from both
    function compoundBalancerRewards(bytes memory _msg) public onlyApproved{

        //claim rewards from merkle orchard -- receives Bal and Qi
        im_merkle.call(_msg);

        //track how much Qi we received, take a fee for owners/creators, compound into vQi
        receivedAirdrop();

        //sell Bal for USDC
        balancerSwap(im_bal, im_usdc, 0x0297e37f1873d2dab4487aa67cd56b58e2f27875000100000000000000000002);
        uint256 usdcBalance = IERC20Upgradeable(im_usdc).balanceOf(address(this));

        //buy GHST with USDC from quickswap using the GHST-USDC LP
        address[] memory path = new address[](2);
                path[0] = im_usdc;
                path[1] = im_ghst;
        Uni(im_qs).swapExactTokensForTokens(usdcBalance, uint256(0),path,address(this),block.timestamp.add(1800));

        //convert GHST to vGHST
        uint256 vGHSTBalance = vGHST(im_vGHST).enter(IERC20Upgradeable(im_ghst).balanceOf(address(this)));
        
        //calculate the profit fee
        uint256 vghst_feeAmount = vGHSTBalance.mul(s.profitFee).div(10000); 
        s.totalFeesCollected += vGHST(im_vGHST).convertVGHST(vghst_feeAmount);

        //send profit fees to owners and creators
        IERC20Upgradeable(im_vGHST).transfer(s.owner, vghst_feeAmount.mul(200).div(400));
        IERC20Upgradeable(im_vGHST).transfer(s.contractCreator, vghst_feeAmount.mul(200).div(400));

        //deposit vGHST as collateral
        QiVault(s.vaultAddress).depositCollateral(s.vaultID, vGHSTBalance.sub(vghst_feeAmount));

    }

    function balancerSwap(address tokenFrom, address tokenTo, bytes32 _poolId) private{

        uint256 balanceA = IERC20Upgradeable(tokenFrom).balanceOf(address(this));

       SingleSwap memory _singleSwap;
        _singleSwap.poolId = _poolId;
        _singleSwap.kind = SwapKind.GIVEN_IN;
        _singleSwap.assetIn = IAsset(tokenFrom);
        _singleSwap.assetOut = IAsset(tokenTo);
        _singleSwap.amount = balanceA;
        _singleSwap.userData = '0x';

        FundManagement memory _fundManagement;
        _fundManagement.sender = address(this);
        _fundManagement.fromInternalBalance = false;
        address _tempAddy = address(this);
        _fundManagement.recipient = payable(_tempAddy);
        _fundManagement.toInternalBalance = false;


        Balancer(im_balancer).swap(
            _singleSwap,
            _fundManagement,
            0,
            MAX_INT
        );
    }

    // function withdrawERC20(address _token) public onlyOwner{
    //     uint256 balance = IERC20Upgradeable(_token).balanceOf(address(this));
    //     IERC20Upgradeable(_token).transfer(msg.sender, balance);
    // }


    //////////////////////////////////////////////////////////////////////////////
    //the following code is taken from OpenZeppelin's ERC20 snapshot contract
    /**
     * @dev Emitted by {_snapshot} when a snapshot identified by `id` is created.
     */
    event Snapshot(uint256 id);

    /**
     * @dev Creates a new snapshot and returns its snapshot id.
     *
     * Emits a {Snapshot} event that contains the same id.
     *
     * {_snapshot} is `internal` and you have to decide how to expose it externally. Its usage may be restricted to a
     * set of accounts, for example using {AccessControl}, or it may be open to the public.
     *
     * [WARNING]
     * ====
     * While an open way of calling {_snapshot} is required for certain trust minimization mechanisms such as forking,
     * you must consider that it can potentially be used by attackers in two ways.
     *
     * First, it can be used to increase the cost of retrieval of values from snapshots, although it will grow
     * logarithmically thus rendering this attack ineffective in the long term. Second, it can be used to target
     * specific accounts and increase the cost of ERC20 transfers for them, in the ways specified in the Gas Costs
     * section above.
     *
     * We haven't measured the actual numbers; if this is something you're interested in please reach out to us.
     * ====
     */
    function _snapshot() internal virtual returns (uint256) {
        s.currentSnapshotId.increment();

        uint256 currentId = _getCurrentSnapshotId();
        emit Snapshot(currentId);
        return currentId;
    }

    function snapshot() public onlyApproved(){
        _snapshot();
    }

    //should be called once a week at the close of the Qi tracking period
    function weeklySnapshot() public onlyApproved{
        _snapshot();
        _snapshot();
        _snapshot();
    }

    /**
     * @dev Get the current snapshotId
     */
    function _getCurrentSnapshotId() internal view virtual returns (uint256) {
        return s.currentSnapshotId.current();
    }

    function getCurrentSnapshotId() public view returns (uint256) {
        return s.currentSnapshotId.current();
    }

    function getCurrentAirdrop() public view returns (uint256) {
        //airdrops started at 1, not 0, so need to do length - 1
        return s.qiAirdrops.length-1;
    }

    /**
     * @dev Retrieves the balance of `account` at the time `snapshotId` was created.
     */
    function balanceOfAt(address account, uint256 snapshotId) public view virtual returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(snapshotId, s.accountBalanceSnapshots[account]);

        return snapshotted ? value : balanceOf(account);
    }

    /**
     * @dev Retrieves the total supply at the time `snapshotId` was created.
     */
    function totalSupplyAt(uint256 snapshotId) public view virtual returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(snapshotId, s.totalSupplySnapshots);

        return snapshotted ? value : totalSupply();
    }

    function qiAirdropAt(uint256 snapshotId) public view returns(uint256) {
        return s.qiAirdrops[snapshotId];
    }

    // Update balance and/or total supply snapshots before the values are modified. This is implemented
    // in the _beforeTokenTransfer hook, which is executed for _mint, _burn, and _transfer operations.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        if (from == address(0)) {
            // mint
            _updateAccountSnapshot(to);
            _updateTotalSupplySnapshot();
        } else if (to == address(0)) {
            // burn
            _updateAccountSnapshot(from);
            _updateTotalSupplySnapshot();
        } else {
            // transfer
            _updateAccountSnapshot(from);
            _updateAccountSnapshot(to);
        }
    }

    function _valueAt(uint256 snapshotId, Snapshots storage snapshots) private view returns (bool, uint256) {
        require(snapshotId > 0, "ERC20Snapshot: id is 0");
        require(snapshotId <= _getCurrentSnapshotId(), "ERC20Snapshot: nonexistent id");

        // When a valid snapshot is queried, there are three possibilities:
        //  a) The queried value was not modified after the snapshot was taken. Therefore, a snapshot entry was never
        //  created for this id, and all stored snapshot ids are smaller than the requested one. The value that corresponds
        //  to this id is the current one.
        //  b) The queried value was modified after the snapshot was taken. Therefore, there will be an entry with the
        //  requested id, and its value is the one to return.
        //  c) More snapshots were created after the requested one, and the queried value was later modified. There will be
        //  no entry for the requested id: the value that corresponds to it is that of the smallest snapshot id that is
        //  larger than the requested one.
        //
        // In summary, we need to find an element in an array, returning the index of the smallest value that is larger if
        // it is not found, unless said value doesn't exist (e.g. when all values are smaller). Arrays.findUpperBound does
        // exactly this.

        uint256 index = snapshots.ids.findUpperBound(snapshotId);

        if (index == snapshots.ids.length) {
            return (false, 0);
        } else {
            return (true, snapshots.values[index]);
        }
    }

    function _updateAccountSnapshot(address account) private {
        _updateSnapshot(s.accountBalanceSnapshots[account], balanceOf(account));
    }

    function _updateTotalSupplySnapshot() private {
        _updateSnapshot(s.totalSupplySnapshots, totalSupply());
    }

    function _updateSnapshot(Snapshots storage snapshots, uint256 currentValue) private {
        uint256 currentId = _getCurrentSnapshotId();
        if (_lastSnapshotId(snapshots.ids) < currentId) {
            snapshots.ids.push(currentId);
            snapshots.values.push(currentValue);
        }
    }

    function _lastSnapshotId(uint256[] storage ids) private view returns (uint256) {
        if (ids.length == 0) {
            return 0;
        } else {
            return ids[ids.length - 1];
        }
    }

    /////////////////////////////////////////////////////////////////////////////////////////
    //this is a non-transferrable token
    function allowance(address, address) public view override returns (uint256)  { return 0; }
    function transfer(address, uint256) public override returns (bool) { return false; }
    function approve(address, uint256) public override returns (bool) { return false; }
    function transferFrom(address, address, uint256) public override returns (bool) { return false; }
}
