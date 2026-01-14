// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../src/LotteryRegistry.sol";
import "../src/SingleWinnerDeployer.sol";
import "../src/LotterySingleWinner.sol";

import "./mocks/MockUSDC.sol";
import "./mocks/MockEntropy.sol";
import "./mocks/RevertingReceiver.sol";

contract BaseTest is Test {
    // Use deterministic Foundry-generated addresses to avoid Solidity 0.8.33 checksum-literal errors
    address internal admin;
    address internal safeOwner;
    address internal creator;
    address internal buyer1;
    address internal buyer2;
    address internal feeRecipient;
    address internal provider;

    LotteryRegistry internal registry;
    SingleWinnerDeployer internal deployer;
    LotterySingleWinner internal lottery;

    MockUSDC internal usdc;
    MockEntropy internal entropy;

    function setUp() public virtual {
        // Deterministic test addresses (no checksum problems)
        admin        = vm.addr(1);
        safeOwner    = vm.addr(2);
        creator      = vm.addr(3);
        buyer1       = vm.addr(4);
        buyer2       = vm.addr(5);
        feeRecipient = vm.addr(6);
        provider     = vm.addr(7);

        vm.startPrank(admin);

        usdc = new MockUSDC();
        entropy = new MockEntropy();
        entropy.setFee(provider, 0.01 ether);

        registry = new LotteryRegistry(admin);

        deployer = new SingleWinnerDeployer(
            admin,
            address(registry),
            safeOwner,
            address(usdc),
            address(entropy),
            provider,
            feeRecipient,
            10 // 10%
        );

        registry.setRegistrar(address(deployer), true);

        vm.stopPrank();

        // Mint balances
        usdc.mint(creator, 50_000_000 * 1e6);
        usdc.mint(buyer1, 50_000_000 * 1e6);
        usdc.mint(buyer2, 50_000_000 * 1e6);

        // Give native ETH to actors
        vm.deal(creator, 100 ether);
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
        vm.deal(admin, 100 ether);
        vm.deal(safeOwner, 100 ether);
        vm.deal(feeRecipient, 100 ether);
    }

    function _deployDefaultLottery() internal returns (LotterySingleWinner lot) {
        vm.startPrank(creator);

        uint256 winningPot = 1_000 * 1e6;
        usdc.approve(address(deployer), winningPot);

        address lotAddr = deployer.createSingleWinnerLottery(
            "Test Lottery",
            2 * 1e6,        // ticket price
            winningPot,     // winning pot
            3,              // minTickets
            0,              // maxTickets (0 = uncapped)
            3600,           // duration seconds
            0               // minPurchaseAmount
        );

        vm.stopPrank();

        lot = LotterySingleWinner(payable(lotAddr));
    }
}