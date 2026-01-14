// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface needed by LotterySingleWinner.
/// Matches what your contract uses: getFee() and requestWithCallback().
interface IEntropy {
    function getFee(address provider) external view returns (uint256);
    function requestWithCallback(address provider, bytes32 userRandomness) external payable returns (uint64);
}