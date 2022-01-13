// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct PoolStakedOutput {
        address poolAddress;
        string poolName;
        string poolUrl;
        uint256 rate;
        uint256 amount;
    }

interface StakingContract{
        function stakeIntoPool(address _poolContractAddress, uint256 _amount) external;

        function withdrawFromPool(address _poolContractAddress, uint256 _amount) external;

        function claimTickets(uint256[] calldata _ids, uint256[] calldata _values) external;

        function convertTickets(uint256[] calldata _ids, uint256[] calldata _values) external;

        function frens(address _account) external view returns (uint256 frens_);

        function setApprovalForAll(address _operator, bool _approved) external;

        function stakedInCurrentEpoch(address _account) external view returns (PoolStakedOutput[] memory _staked);

            function balanceOf(address _owner, uint256 _id) external view  returns (uint256 balance_) ;


}