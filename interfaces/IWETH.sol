// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}
