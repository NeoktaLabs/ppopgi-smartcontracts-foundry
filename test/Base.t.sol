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
    // Valid hex-only addresses (20-byte recommended)
    address internal admin        = address(0x000000000000000000000000000000000000A11C);
    address internal safeOwner    = address(0x0000000000000000000000000000000000005AFE);
    address internal creator      = address(0x0000000000000000000000000000000000C0FFEE);
    address internal buyer1       = address(0x000000000000000000000000000000000000B001);
    address internal buyer2       = address(0x000000000000000000000000000000000000B002);
    address internal feeRecipient = address(0x000000000000000000000000000000000000FEE1);
    address internal provider     = address(0x0000000000000000000000000000000000001234);

    LotteryRegistry internal registry;
    SingleWinnerDeployer internal deployer;
    LotterySingleWinner internal lottery;

    MockUSDC internal usdc;
    MockEntropy internal entropy;

    function setUp() public virtual {
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