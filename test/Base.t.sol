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
    address internal admin = address(0xA11CE);
    address internal safeOwner = address(0xSAFE);
    address internal creator = address(0xC0FFEE);
    address internal buyer1 = address(0xB001);
    address internal buyer2 = address(0xB002);
    address internal feeRecipient = address(0xFEE1);
    address internal provider = address(0xPR0V);

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
            10
        );

        registry.setRegistrar(address(deployer), true);
        vm.stopPrank();

        usdc.mint(creator, 50_000_000 * 1e6);
        usdc.mint(buyer1, 50_000_000 * 1e6);
        usdc.mint(buyer2, 50_000_000 * 1e6);

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
            2 * 1e6,
            winningPot,
            3,
            0,
            3600,
            0
        );

        vm.stopPrank();

        lot = LotterySingleWinner(payable(lotAddr));
    }
}