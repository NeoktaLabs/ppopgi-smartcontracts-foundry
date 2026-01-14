function test_CreateLottery_InitialStateCorrect() public {
    vm.startPrank(creator);
    usdc.approve(address(deployer), type(uint256).max);

    address lotAddr = deployer.createSingleWinnerLottery(
        "Creation Test",
        2 * 1e6,
        500 * 1e6,
        3,
        10,
        3600,
        0
    );
    vm.stopPrank();

    LotterySingleWinner l = LotterySingleWinner(payable(lotAddr));

    // Core invariants
    assertEq(uint256(l.status()), uint256(LotterySingleWinner.Status.Open));
    assertEq(l.creator(), creator);
    assertEq(l.owner(), safeOwner);
    assertEq(l.ticketPrice(), 2 * 1e6);
    assertEq(l.winningPot(), 500 * 1e6);
    assertEq(l.minTickets(), 3);
    assertEq(l.maxTickets(), 10);

    // Funding accounted
    assertEq(l.totalReservedUSDC(), 500 * 1e6);
    assertEq(usdc.balanceOf(address(l)), 500 * 1e6);
}