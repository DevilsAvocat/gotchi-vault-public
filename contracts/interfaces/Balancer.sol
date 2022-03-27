//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

struct ExitPoolRequest {
    IAsset[] assets;
    uint256[] minAmountsOut;
    bytes userData;
    bool toInternalBalance;
}

enum SwapKind { GIVEN_IN, GIVEN_OUT }

interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}

struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
}

struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

interface Balancer{
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external;

    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external;
}

enum JoinKind { 
    INIT, 
    EXACT_TOKENS_IN_FOR_BPT_OUT, 
    TOKEN_IN_FOR_EXACT_BPT_OUT
 }

 enum ExitKind { 
    EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, 
    EXACT_BPT_IN_FOR_TOKENS_OUT, 
    BPT_IN_FOR_EXACT_TOKENS_OUT 
}