// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct TicketItemIO {
        address ticketAddress; // ERC1155 contract address (entry ticket), not prize
        uint256 ticketId; // ERC1155 type id
        uint256 ticketQuantity; // Number of ERC1155 tokens
    }
struct ticketWinIO {
        uint256 entryIndex; // index into a user's array of tickets (which staking attempt won)
        PrizesWinIO[] prizes;
    }
struct PrizesWinIO {
        uint256 raffleItemPrizeIndex; // index into the raffleItemPrizes array (which prize was won)
        uint256[] winningPrizeNumbers; // ticket numbers between 0 and raffleItem.totalEntered that won
    }

interface RaffleContract{
    function enterTickets(uint256 _raffleId, TicketItemIO[] calldata _ticketItems) external;

    function claimPrize(
        uint256 _raffleId,
        address _entrant,
        ticketWinIO[] calldata _wins
    ) external;

    
}