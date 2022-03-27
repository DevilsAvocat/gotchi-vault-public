// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./interfaces/IeQi.sol";


contract vQi is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable{

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public owner;

    address public constant eQiAddress = 0x880DeCADe22aD9c58A8A4202EF143c4F305100B3;
    address public constant QiAddress = 0x580A84C73811E1839F75d86d75d88cCa0c241fF4;

    uint256 constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    IeQi constant eQi = IeQi(eQiAddress);
    ERC20Upgradeable constant Qi = ERC20Upgradeable(QiAddress);

    function initialize(
        address _owner,
        string memory name, 
        string memory symbol
        ) public initializer{

        __ERC20_init(name, symbol);

        owner = _owner;

        //need to approve the eQi contract to take all our Qi
        Qi.approve(eQiAddress, MAX_INT);

    }

    modifier onlyOwner() {
        require(msg.sender ==  owner, "onlyOwner: not allowed");
        _;
    }

    function pause(bool _setPause) public onlyOwner{
        if(_setPause){_pause();}
        else _unpause();
    }

    function updateOwner(address _owner) public onlyOwner {
        owner = _owner;
    }

    function enter(uint256 _amount) public whenNotPaused nonReentrant {

        //user can't mint more vQi than he has Qi
        require(Qi.balanceOf(msg.sender) >= _amount, "enter: insufficient qi balance to deposit");
        //must have approved the vQi contract to take Qi
        require(Qi.allowance(msg.sender, address(this)) >= _amount, "enter: must approve vQi contract to withdraw Qi");

        //pull in the user's requested amount of Qi
        Qi.transferFrom(msg.sender, address(this), _amount);

        UserInfo memory myInfo = eQi.userInfo(address(this));
        
        uint256 endBlock = myInfo.endBlock;
        uint256 blocksLeft = endBlock - block.number;
        uint256 timeToAdd = 60108430 - blocksLeft;

        //lock up the user's Qi into eQi for the max amount (60108430 is the max number of blocks, hard coded into the eQi contract)
        eQi.enter(_amount, timeToAdd);

        //we mint vQi directly to the sender at a 1:1 ratio
        _mint(msg.sender, _amount);
    }

    //this function allows the owner to lock up Qi held by the contract into eQi without minting more vQi
    function lockQi(uint256 _amount) public onlyOwner {
        UserInfo memory myInfo = eQi.userInfo(address(this));
        
        uint256 endBlock = myInfo.endBlock;
        uint256 blocksLeft = endBlock - block.number;
        uint256 timeToAdd = 60108430 - blocksLeft;

        //lock up the Qi into eQi for the max amount (60108430 is the max number of blocks, hard coded into the eQi contract)
        eQi.enter(_amount, timeToAdd);
    }

    //allow the owner to withdraw all Qi rewards -- need to do this to pass through the airdrops
    function withdrawQi() public onlyOwner{
        Qi.transfer(owner, Qi.balanceOf(address(this)));
    }

    function eQiBalance() public view returns(uint256){
        return eQi.balanceOf(address(this));
    }

    function underlyingBalance() public view returns(uint256){
        return eQi.underlyingBalance(address(this));
    }

}