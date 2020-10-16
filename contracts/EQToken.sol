// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@nomiclabs/buidler/console.sol";

contract EQToken is ERC1155 {
    string public name = "EQ Token";
    // Token IDs
    uint256 public constant PLATINUM = 0;
    uint256 public constant CLERIC = 1;
    uint256 public constant DRUID = 2;
    uint256 public constant MAGE = 3;
    uint256 public constant MONK = 4;
    uint256 public constant RANGER = 5;
    uint256 public constant WARRIOR = 6;

    constructor() public ERC1155("http://127.0.0.1:8080/api/character/{1}.json") {
        _mint(msg.sender, CLERIC, 1, "");
        _mint(msg.sender, DRUID, 1, "");
        _mint(msg.sender, MAGE, 1, "");
        _mint(msg.sender, MONK, 1, "");
        _mint(msg.sender, RANGER, 1, "");
        _mint(msg.sender, WARRIOR, 1, "");
        // use PLAT to buy cards
        // PLATINUM is earned by stakers
        _mint(msg.sender, PLATINUM, 10**27, ""); // max number
    }

    function platinumID() public pure returns (uint256)
    {
        return PLATINUM;
    }

    function mintPlatinumFor(address _recipient, uint256 _amount) public
    {
        _mint(_recipient, PLATINUM, _amount, "");
    }
}
