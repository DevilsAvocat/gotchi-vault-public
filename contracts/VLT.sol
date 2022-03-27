// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

contract VLT is ERC20Capped{
    //decimals defaults to 18 in IERC20
    constructor(string memory name_, string memory symbol_,uint256 _cap, address _treasury) ERC20Capped(_cap) ERC20(name_, symbol_){   
            _mint(_treasury, _cap);
    }
}