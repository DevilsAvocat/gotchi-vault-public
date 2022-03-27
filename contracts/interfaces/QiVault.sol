//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface QiVault{

    function createVault() external returns (uint256);

    function depositCollateral(uint256 vaultID, uint256 amount) external;

    function withdrawCollateral(uint256 vaultID, uint256 amount) external;

    function borrowToken(uint256 vaultID, uint256 amount) external;

    function payBackToken(uint256 vaultID, uint256 amount) external;

    function checkCollateralPercentage(uint256 vaultID) external view returns(uint256);

    function vaultCollateral(uint256 vaultId) external view returns (uint256);
    
    function vaultDebt(uint256 vaultId) external view returns (uint256);

    function getEthPriceSource() external view returns (uint256);
    function getTokenPriceSource() external view returns (uint256);


}