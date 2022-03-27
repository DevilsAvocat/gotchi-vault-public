// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.7;

import "./interfaces/IFlashLoanRecipient.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";


interface Balancer {

    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}


interface MaiVault is IERC721  {

    function createVault() external returns (uint256);

    function vaultDebt(uint256 vaultId) external view returns (uint256);

    function vaultCollateral(uint256 vaultId) external view returns (uint256);

    function payBackToken(uint256 vaultID, uint256 amount) external;

    function withdrawCollateral(uint256 vaultID, uint256 amount) external;

    function depositCollateral(uint256 vaultID, uint256 amount) external;

    function borrowToken(uint256 vaultID, uint256 amount) external;
}


interface vGHST {
    function enter(uint256 _amount) external returns(uint256);
}

contract vGHSTZapper is IFlashLoanRecipient {
   
    using SafeMath for uint256;
    
    address internal constant balancerAddress = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant mimaticAddress = 0xa3Fa99A148fA48D14Ed51d610c367C61876997F1;
    address internal constant ghstAddress = 0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7;
    address internal constant ghstVaultAddress = 0xF086dEdf6a89e7B16145b03a6CB0C0a9979F1433;
    address internal constant vGHSTaddress = 0x51195e21BDaE8722B29919db56d95Ef51FaecA6C;
    uint256 internal constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address public vGhstVaultAddress = 0x1F0aa72b980d65518e88841bA1dA075BD43fa933;

    Balancer balancer = Balancer(balancerAddress);

    ERC20 mimatic = ERC20(mimaticAddress);
    ERC20 ghst = ERC20(ghstAddress);
    ERC20 vGhst = ERC20(vGHSTaddress);

    MaiVault private ghstVault = MaiVault(ghstVaultAddress);
    MaiVault private vGhstVault = MaiVault(vGhstVaultAddress);

    uint256 private VaultID;
    address public admin;

    constructor()  {
        
        admin = msg.sender;

        //set approvals
        //GHST vault contract must take our Mai
        mimatic.approve(ghstVaultAddress, MAX_INT);

        //vGHST must take our GHST
        ghst.approve(vGHSTaddress, MAX_INT);

        //vGHST vault contract must take our vGHST
        vGhst.approve(vGhstVaultAddress, MAX_INT);
    }
    
    
    /**
        This function is called after your contract has received the flash loaned amount
     */
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    )
        external
        override
    {
        userData; //do nothing -- clear warning
        
        //repay the mai debt on the vault the user has sent -- this will trigger the 0.5% Mai repayment fee
        ghstVault.payBackToken(VaultID, amounts[0]);

        //withdraw all the GHST collateral 
        uint256 vaultCollateral = ghstVault.vaultCollateral(VaultID);
        ghstVault.withdrawCollateral(VaultID, vaultCollateral);

        //deposit the GHST into vGHST
        uint256 vGHSTAmount = vGHST(vGHSTaddress).enter(vaultCollateral);

        //create a new vGHST vault
        uint256 newVaultId = vGhstVault.createVault();

        //deposit vGHST into vault
        vGhstVault.depositCollateral(newVaultId, vGHSTAmount);

        //borrow back mai to repay debt to balancer
        vGhstVault.borrowToken(newVaultId, amounts[0]);

        //send the vaults back to original user
        ghstVault.safeTransferFrom(address(this), tx.origin, VaultID);
        vGhstVault.safeTransferFrom(address(this), tx.origin, newVaultId);

        // Approve the LendingPool contract allowance to *pull* the owed amount
        // i.e. AAVE V2's way of repaying the flash loan
        for (uint i = 0; i < tokens.length; i++) {
            uint amountOwing = amounts[i].add(feeAmounts[i]);
            IERC20(tokens[i]).transfer(balancerAddress, amountOwing);
        }

    }

    /*
    * This function is manually called to commence the flash loans sequence
    * Must be called by the user who holds the GHST vault, and must have given this contract approval
    */
    function executeFlashLoan(uint256 _VaultID) public {

        //require that msg.sender owns the vault
        require(ghstVault.ownerOf(_VaultID) == msg.sender, "ExecuteFlashLoan: only may be called by owner");

        //require that we are authorized to pull the vault
        require(ghstVault.isApprovedForAll(msg.sender,address(this)),"ExecuteFlashLoan: Must approve this contract to take vault");
        
        //need to take note of the vaultId for later
        VaultID = _VaultID;

        //transfer the Qidao vault to this contract
        ghstVault.safeTransferFrom(msg.sender,address(this),_VaultID);

        //check how much debt is needed
        uint256 maiDebt = ghstVault.vaultDebt(_VaultID);

        // the various assets to be flashed
        //we are borrowing mimatic from Balancer
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = mimatic;

        // the amount to be flashed for each asset
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = maiDebt ;


        balancer.flashLoan(
            this,
            assets,
            amounts,
            ""
        );

        
    }

    function onERC721Received(
        address, /* _operator */
        address, /*  _from */
        uint256, /*  _tokenId */
        bytes calldata /* _data */
    ) external pure  returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
   
 
   
}