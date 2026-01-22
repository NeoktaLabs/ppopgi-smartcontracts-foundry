// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Entropy interface required by LotterySingleWinner.
interface IEntropyV2 {
    function getFee(address provider) external view returns (uint256);
    function requestWithCallback(address provider, bytes32 userRandomness) external payable returns (uint64);
}