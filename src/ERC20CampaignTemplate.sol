// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CampaignToken is ERC20 {
    address public campaignCreator;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
