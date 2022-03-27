//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface Merkle {

    struct Claim {
        uint256 distributionId; //id of the distribution, generally starting at 1
        uint256 balance; //the number of tokens being claimed (in wei), as sourced from the published distributions 
        address distributor; //the address that added the tokens 
        uint256 tokenIndex; //the index of the token being claimed (index of the address in the tokens parameter) 
        bytes32[] merkleProof; //an array of hashes that prove the validity of the claim 
    }
    /**
     * @notice Allows anyone to claim multiple distributions for a claimer.
     */
    function claimDistributions(
        address claimer, //the address of the account claiming tokens) 
        Claim[] memory claims, //an array of the claim structs that describes the claim being made
        IERC20[] memory tokens //an array of the set of all tokens being claimed, referenced by tokenIndex. Tokens can be in any order so long as they are indexed correctly.
    ) external;
}