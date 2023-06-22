// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IZkSyncSwapCallee {
    function zkSyncSwapCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
