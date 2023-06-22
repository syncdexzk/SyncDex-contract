// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ZKS is ERC20, Ownable {
    constructor(uint256 initialSupply) ERC20("ZKS token", "ZKS") {
        _mint(msg.sender, initialSupply);
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}