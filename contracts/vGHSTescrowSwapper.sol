// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./interfaces/IAavegotchi.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./vGHST.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract vGHSTescrowSwapper is IERC721Receiver{

    address internal constant im_diamondAddress = 0x86935F11C86623deC8a25696E1C19a8659CbF95d;
    address internal constant im_vGHSTAddress = 0x51195e21BDaE8722B29919db56d95Ef51FaecA6C;
    address internal constant im_ghstAddress = 0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7;
    uint256 internal constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address owner;

    constructor() {

        owner = msg.sender;
        ERC20(im_ghstAddress).approve(im_vGHSTAddress, MAX_INT);

    }

    //we allow users to directly enter GHST from their gotchis' pocket into the pool without directly receiving
    //the GHST to the user address
    function compoundEscrow(uint256 _tokenId) public {
        require(IERC721(im_diamondAddress).ownerOf(_tokenId) == msg.sender,"only may be called by the owner of the gotchi");
        
        //we get the amount of GHST in the escrow -- must be more than 0
        uint256 escrowBalance = IAavegotchi(im_diamondAddress).escrowBalance(_tokenId, im_ghstAddress);
        require(escrowBalance > 0, "Fail: this gotchi has no GHST in pocket");

        //transfer the gotchi from the user to the contract
        IERC721(im_diamondAddress).safeTransferFrom(msg.sender, address(this), _tokenId);

        //transfer the escrow from the gotchi pocket to address(this)
        IAavegotchi(im_diamondAddress).transferEscrow(_tokenId, im_ghstAddress, address(this), escrowBalance);

        //deposit the GHST into vGHST contract
        uint256 vGHSTReturned = vGHST(im_vGHSTAddress).enter(escrowBalance);

        //now send the vGHST back to the gotchi's wallet
        address escrowAddress = IAavegotchi(im_diamondAddress).gotchiEscrow(_tokenId);
        vGHST(im_vGHSTAddress).transfer(escrowAddress,vGHSTReturned);

        //finally, send the gotchi back to its owneer
        IERC721(im_diamondAddress).safeTransferFrom(address(this),msg.sender, _tokenId);
    }

    /*function doSomething(address _addr, bytes memory _msg) public {
        require(msg.sender == owner);
        _addr.call(_msg);
    }*/

 
      function onERC721Received(
        address, /* _operator */
        address, /*  _from */
        uint256, /*  _tokenId */
        bytes calldata /* _data */
    ) external pure  returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

}