// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8;

struct UserInfo {
        uint256 amount;
        uint256 endBlock;
    }

interface IeQi {

    function enter(uint256 _amount, uint256 _blockNumber) external;

    function userInfo(address) external view returns(UserInfo memory);

    function leave() external;

    //how much eQi
    function balanceOf(address user) external view returns(uint256);

    function underlyingBalance(address user) external view returns(uint256);
}