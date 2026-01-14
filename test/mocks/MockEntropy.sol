// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../src/vendor/pyth/IEntropy.sol";

interface IEntropyConsumer {
    function entropyCallback(uint64 sequenceNumber, address provider, bytes32 randomNumber) external;
}

contract MockEntropy is IEntropy {
    uint64 public nextSeq = 1;

    mapping(address => uint256) public feeOf;

    struct Req {
        address consumer;
        address provider;
        bool exists;
    }

    mapping(uint64 => Req) public reqs;

    function setFee(address provider, uint256 fee) external {
        feeOf[provider] = fee;
    }

    function getFee(address provider) external view returns (uint256) {
        return feeOf[provider];
    }

    function requestWithCallback(address provider, bytes32) external payable returns (uint64) {
        uint256 fee = feeOf[provider];
        require(msg.value >= fee, "fee too low");

        uint64 id = nextSeq++;
        reqs[id] = Req({consumer: msg.sender, provider: provider, exists: true});
        return id;
    }

    function fulfill(uint64 id, bytes32 rand) external {
        Req memory r = reqs[id];
        require(r.exists, "unknown request");

        IEntropyConsumer(r.consumer).entropyCallback(id, r.provider, rand);
        delete reqs[id];
    }
}