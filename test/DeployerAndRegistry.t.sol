// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";

contract DeployerAndRegistryTest is BaseTest {
    function test_DeployerRequiresRegistrarAuth() public {
        vm.prank(admin);
        registry.setRegistrar(address(deployer), false);

        vm.startPrank(creator);
        usdc.approve(address(deployer), 1_000 * 1e6);

        vm.expectRevert(SingleWinnerDeployer.NotAuthorizedRegistrar.selector);
        deployer.createSingleWinnerLottery("X", 2e6, 1_000e6, 1, 0, 3600, 0);
        vm.stopPrank();
    }

    function test_FactoryDeployFlow_SetsOwnerAndFunding() public {
        LotterySingleWinner lot = _deployDefaultLottery();

        assertEq(lot.owner(), safeOwner);
        assertEq(lot.creator(), creator);
        assertEq(uint256(lot.status()), uint256(LotterySingleWinner.Status.Open));
        assertEq(lot.totalReservedUSDC(), lot.winningPot());

        assertTrue(registry.typeIdOf(address(lot)) != 0);
        assertEq(registry.creatorOf(address(lot)), creator);
    }

    function test_RegistryPaginationEmpty() public {
        address[] memory page = registry.getAllLotteries(0, 0);
        assertEq(page.length, 0);
        page = registry.getAllLotteries(999, 10);
        assertEq(page.length, 0);
    }
}