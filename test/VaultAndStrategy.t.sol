// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract VaultAndStrategyTest is TestHelper {
    IAggregatorV3 dfX;
    IAggregatorV3 dfY;

    function setUp() public override {
        super.setUp();

        dfX = new MockAggregator();
        dfY = new MockAggregator();

        vm.prank(owner);
        (vault, strategy) = factory.createOracleVaultAndDefaultStrategy(ILBPair(wavax_usdc_20bp), dfX, dfY);
    }

    function test_DepositToVault() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        (uint256 shares, uint256 x, uint256 y) = IOracleVault(vault).previewShares(1e18, 1e6);

        assertEq(x, 1e18, "test_DepositToVault::1");
        assertEq(y, 1e6, "test_DepositToVault::2");

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(x, y);
        vm.stopPrank();

        assertEq(IERC20Upgradeable(wavax).balanceOf(strategy), 1e18, "test_DepositToVault::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(strategy), 1e6, "test_DepositToVault::4");

        assertEq(IOracleVault(vault).balanceOf(vault), 1e6, "test_DepositToVault::5");
        assertEq(IOracleVault(vault).balanceOf(alice), shares - 1e6, "test_DepositToVault::6");
    }

    function test_DepositToVaultTwice() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        deal(wavax, bob, 1e18);
        deal(usdc, bob, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (uint256 shares, uint256 x, uint256 y) = IOracleVault(vault).previewShares(1e18, 1e6);

        assertEq(x, 1e18, "test_DepositToVaultTwice::1");
        assertEq(y, 1e6, "test_DepositToVaultTwice::2");

        vm.startPrank(bob);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        assertEq(IERC20Upgradeable(wavax).balanceOf(strategy), 2e18, "test_DepositToVaultTwice::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(strategy), 2e6, "test_DepositToVaultTwice::4");

        assertEq(IOracleVault(vault).balanceOf(bob), shares, "test_DepositToVaultTwice::5");
        assertEq(
            IOracleVault(vault).balanceOf(bob),
            IOracleVault(vault).balanceOf(alice) + 1e6,
            "test_DepositToVaultTwice::6"
        );
    }

    function test_WithdrawFromVaultDirect() external {
        depositToVault(vault, alice, 1e18, 20e6);

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        (uint256 x, uint256 y) = IOracleVault(vault).previewAmounts(shares);

        assertEq(x, 1e18 * shares / (shares + 1e6), "test_WithdrawFromVault::1");
        assertEq(y, 20e6 * shares / (shares + 1e6), "test_WithdrawFromVault::2");

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        IOracleVault(vault).redeemQueuedWithdrawal(0, alice);

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), x, "test_WithdrawFromVault::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), y, "test_WithdrawFromVault::4");

        assertEq(
            IERC20Upgradeable(wavax).balanceOf(strategy),
            (1e18 * 1e6 - 1) / (shares + 1e6) + 1,
            "test_WithdrawFromVault::5"
        );
        assertEq(
            IERC20Upgradeable(usdc).balanceOf(strategy),
            (20e6 * 1e6 - 1) / (shares + 1e6) + 1,
            "test_WithdrawFromVault::6"
        );

        assertEq(IOracleVault(vault).balanceOf(alice), 0, "test_WithdrawFromVault::7");
    }

    function test_WithdrawFromVaultAfterdepositWithDistributions() external {
        depositToVault(vault, alice, 1e18, 20e6);
        uint256 shares = IOracleVault(vault).balanceOf(alice);

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory amountsInY = new uint256[](3);
        (amountsInY[0], amountsInY[1], amountsInY[2]) = (20e6, 100e6, 20e6);

        vm.prank(owner);

        IStrategy(strategy).rebalance(0, 2, 0, type(uint24).max, amountsInY, 1e18, 1e18);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        IOracleVault(vault).redeemQueuedWithdrawal(0, alice);

        uint256 price = router.getPriceFromId(ILBPair(wavax_usdc_20bp), uint24(activeId));

        uint256 depositInY = ((price * 1e18) >> 128) + 20e6;
        uint256 receivedInY =
            ((price * IERC20Upgradeable(wavax).balanceOf(alice)) >> 128) + IERC20Upgradeable(usdc).balanceOf(alice);

        assertApproxEqRel(receivedInY, depositInY, 1e15, "test_WithdrawFromVaultAfterdepositWithDistributions::1");
    }

    function test_DepositAndWithdrawWithFees() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory amountsInY = new uint256[](3);
        (amountsInY[0], amountsInY[1], amountsInY[2]) = (100e6, 20e6, 200e6);

        vm.prank(owner);
        IStrategy(strategy).rebalance(1, 3, 2, type(uint24).max, amountsInY, 1e18, 1e18);

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        {
            deal(usdc, bob, 100_000e6);
            vm.prank(bob);
            IERC20Upgradeable(usdc).transfer(wavax_usdc_20bp, 100_000e6);

            ILBPair(wavax_usdc_20bp).swap(false, bob);

            deal(wavax, bob, 10_000e18);

            vm.prank(bob);
            IERC20Upgradeable(wavax).transfer(wavax_usdc_20bp, 10_000e18);

            ILBPair(wavax_usdc_20bp).swap(true, bob);

            deal(usdc, bob, 200_000e6);
            vm.prank(bob);
            IERC20Upgradeable(usdc).transfer(wavax_usdc_20bp, 200_000e6);

            ILBPair(wavax_usdc_20bp).swap(false, bob);
        }

        vm.prank(alice);
        IOracleVault(vault).queueWithdrawal(shares, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        IOracleVault(vault).redeemQueuedWithdrawal(0, alice);

        uint256 price = router.getPriceFromId(ILBPair(wavax_usdc_20bp), uint24(activeId));

        uint256 depositInY = ((price * 1e18) >> 128) + 1e6;
        uint256 receivedInY =
            ((price * IERC20Upgradeable(wavax).balanceOf(alice)) >> 128) + IERC20Upgradeable(usdc).balanceOf(alice);

        assertGt(receivedInY, depositInY, "test_DepositAndWithdrawWithFees::2");
    }

    function test_DepositAndWithdrawNoActive() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory amountsInY = new uint256[](3);
        (amountsInY[0], amountsInY[1], amountsInY[2]) = (50e6, 200e6, 1000e6);

        vm.prank(owner);
        IStrategy(strategy).rebalance(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, amountsInY, 1e18, 1e18
        );

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        vm.prank(alice);
        IOracleVault(vault).queueWithdrawal(shares / 100_000, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        IOracleVault(vault).redeemQueuedWithdrawal(0, alice);

        assertGt(IERC20Upgradeable(wavax).balanceOf(alice), 0, "test_DepositAndWithdrawNoActive::1");
        assertGt(IERC20Upgradeable(usdc).balanceOf(alice), 0, "test_DepositAndWithdrawNoActive::2");
    }

    function test_DepositAndCollectFees() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory amountsInY = new uint256[](5);
        (amountsInY[0], amountsInY[1], amountsInY[2], amountsInY[3], amountsInY[4]) = (100e6, 20e6, 200e6, 100e6, 100e6);

        vm.startPrank(owner);
        factory.setPendingAumAnnualFee(IBaseVault(vault), 0.1e4);
        IStrategy(strategy).rebalance(
            uint24(activeId) - 2, uint24(activeId) + 2, uint24(activeId), 0, amountsInY, 1e18, 1e18
        );
        vm.stopPrank();

        {
            deal(usdc, bob, 100_000e6);
            vm.prank(bob);
            IERC20Upgradeable(usdc).transfer(wavax_usdc_20bp, 100_000e6);

            ILBPair(wavax_usdc_20bp).swap(false, bob);

            deal(wavax, bob, 10_000e18);

            vm.prank(bob);
            IERC20Upgradeable(wavax).transfer(wavax_usdc_20bp, 10_000e18);

            ILBPair(wavax_usdc_20bp).swap(true, bob);

            deal(usdc, bob, 200_000e6);
            vm.prank(bob);
            IERC20Upgradeable(usdc).transfer(wavax_usdc_20bp, 200_000e6);

            ILBPair(wavax_usdc_20bp).swap(false, bob);
        }

        uint256 balanceX = IERC20Upgradeable(wavax).balanceOf(strategy);
        uint256 balanceY = IERC20Upgradeable(usdc).balanceOf(strategy);

        IStrategy(strategy).collectFees();

        assertGt(IERC20Upgradeable(wavax).balanceOf(strategy), balanceX, "test_DepositAndCollectFees::1");
        assertGt(IERC20Upgradeable(usdc).balanceOf(strategy), balanceY, "test_DepositAndCollectFees::2");
    }

    function test_DepositAndSetStrategy() external {
        depositToVault(vault, alice, 25e18, 400e6);

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory amountsInY = new uint256[](3);
        (amountsInY[0], amountsInY[1], amountsInY[2]) = (100e6, 200e6, 100e6);

        vm.startPrank(owner);
        IStrategy(strategy).rebalance(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, amountsInY, 1e18, 1e18
        );

        uint256 shares = IOracleVault(vault).balanceOf(alice);
        (uint256 amountX, uint256 amountY) = IBaseVault(vault).previewAmounts(shares);

        address newStrategy = factory.createDefaultStrategy(IBaseVault(vault));
        factory.linkVaultToStrategy(IBaseVault(vault), newStrategy);
        vm.stopPrank();

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        vm.startPrank(owner);
        vm.expectRevert(IBaseVault.BaseVault__OnlyStrategy.selector);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        IStrategy(newStrategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);
        vm.stopPrank();

        IBaseVault(vault).redeemQueuedWithdrawal(0, alice);

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), amountX, "test_DepositAndSetStrategy::1");
        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), amountY, "test_DepositAndSetStrategy::2");
    }

    function test_DepositAndEmergencyWithdraw() external {
        depositToVault(vault, alice, 25e18, 400e6);

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory amountsInY = new uint256[](3);
        (amountsInY[0], amountsInY[1], amountsInY[2]) = (100e6, 200e6, 100e6);

        vm.startPrank(owner);
        IStrategy(strategy).rebalance(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, amountsInY, 1e18, 1e18
        );

        (uint256 amountX, uint256 amountY) = IBaseVault(vault).previewAmounts(IOracleVault(vault).balanceOf(alice));

        factory.setEmergencyMode(IBaseVault(vault));
        vm.stopPrank();

        vm.prank(alice);
        IOracleVault(vault).emergencyWithdraw();

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), amountX, "test_DepositAndEmergencyWithdraw::1");
        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), amountY, "test_DepositAndEmergencyWithdraw::2");
    }
}
