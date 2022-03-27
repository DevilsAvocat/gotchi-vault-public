// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/IAavegotchi.sol";
import "./GotchiVault.sol";
import "./VLT.sol";

contract VLTClaim is Initializable, PausableUpgradeable {
    using SafeMath for uint256;

    address owner;
    address diamondAddress;
    address vaultAddress;
    address VLTAddress;

    //the number of tokens each gotchi is entitled to
    uint256 tokensPerGotchi;

    //a mapping of whether individual gotchis have been claimed yet
    mapping(uint256 => bool) claimed;

    function initialize(
            address _owner,
            uint256 _tokensPerGotchi,
            address _VLTAddress,
            address _diamondAddress,
            address _vaultAddress
        ) public initializer{

        owner = _owner;
        tokensPerGotchi = _tokensPerGotchi;
        VLTAddress = _VLTAddress;
        diamondAddress = _diamondAddress;
        vaultAddress = _vaultAddress;
    }

    modifier onlyOwner{
        require(msg.sender == owner);
        _;
    }

    function getOwner() public view returns(address){
        return owner;
    }

    function setOwner(address _owner) public onlyOwner{
        owner = _owner;
    }

    function setTokensPerGotchi(uint256 _tokensPerGotchi) public onlyOwner{
        tokensPerGotchi = _tokensPerGotchi;
    }

    function pause(bool _setPause) public onlyOwner{
        if(_setPause){_pause();}
        else _unpause();
    }

    function getGotchisInWallet(address _user) public view returns(uint32[] memory _tokenIds){
        return IAavegotchi(diamondAddress).tokenIdsOfOwner(_user);
    }

    function getGotchisInVault(address _user) public view returns(uint256[] memory) {
        return GotchiVault(vaultAddress).getTokenIdsOfDepositor(_user,diamondAddress);
    }

    function hasBeenClaimed(uint256 _tokenId) public view returns (bool){
        return claimed[_tokenId]; 
    }

    function VLTEligible(uint256[] calldata gotchisInWallet, uint256[] calldata gotchisInVault) public view returns(uint256 VLTtoSend){

        for(uint256 i = 0; i < gotchisInWallet.length; i++){
            if(claimed[gotchisInWallet[i]] == false){VLTtoSend += tokensPerGotchi;}
        }
        for(uint256 i = 0; i < gotchisInVault.length; i++){
            if(claimed[gotchisInVault[i]] == false){VLTtoSend += tokensPerGotchi;}
        }
        
    }

    function claimVLT() public{

        require(VLT(VLTAddress).balanceOf(address(this)) > 0, "claimVLT: there is no VLT to be claimed");

        //we get a list of all the senders' gotchis in their wallet, and in the vault
        uint32[] memory gotchisInWallet = getGotchisInWallet(msg.sender);
        uint256[] memory gotchisInVault = getGotchisInVault(msg.sender);

        //add the lengths up to find the total gotchis this owner has
        uint256 totalGotchis = gotchisInWallet.length + gotchisInVault.length;
        require(totalGotchis > 0,"claimVLT: sender not eligible for any VLT");
        uint256 VLTtoSend;

        //got through and mark as claimed all the gotchis
        for(uint256 i = 0; i < gotchisInWallet.length; i++){
            if(claimed[gotchisInWallet[i]] == false){VLTtoSend += tokensPerGotchi;}
            claimed[gotchisInWallet[i]] = true;
        }
        for(uint256 i = 0; i < gotchisInVault.length; i++){
            if(claimed[gotchisInVault[i]] == false){VLTtoSend += tokensPerGotchi;}
            claimed[gotchisInVault[i]] = true;
        }

        uint256 VLTBalance = VLT(VLTAddress).balanceOf(address(this));
        require(VLTBalance > VLTtoSend, "claimVLT: attempting to claim more than total VLT");

        require(VLTtoSend > 0, "claimVLT: sender not eligible for any VLT");
        //finally, send the user his tokens
        VLT(VLTAddress).transfer(msg.sender, VLTtoSend);
    }

    //to be called by the owner at the end of the claiming period
    function withdrawAllVLT(address _destination) public onlyOwner{
        uint256 VLTBalance = VLT(VLTAddress).balanceOf(address(this));
        VLT(VLTAddress).transfer(_destination, VLTBalance);
    }
}