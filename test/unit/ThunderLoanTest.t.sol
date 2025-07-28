// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { BaseTest, ThunderLoan, ThunderLoanUpgraded } from "./BaseTest.t.sol";
import { AssetToken } from "../../src/protocol/AssetToken.sol";
import { MockFlashLoanReceiver } from "../mocks/MockFlashLoanReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ThunderLoanTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address liquidityProvider2 = address(456);
    address user = address(789);
    MockFlashLoanReceiver mockFlashLoanReceiver;

    event Redeemed(
        address indexed account, IERC20 indexed token, uint256 amountOfAssetToken, uint256 amountOfUnderlying
    );

    function setUp() public override {
        super.setUp();
        vm.prank(user);
        mockFlashLoanReceiver = new MockFlashLoanReceiver(address(thunderLoan));
    }

    function testInitializationOwner() public view {
        assertEq(thunderLoan.owner(), address(this));
    }

    function testSetAllowedTokens() public {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        assertEq(thunderLoan.isAllowedToken(tokenA), true);
    }

    function testSetAllowedTokenRevertsIfAlreadyAllowed() public {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        vm.expectRevert(ThunderLoan.ThunderLoan__AlreadyAllowed.selector);
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testOnlyOwnerCanSetTokens() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testSettingTokenCreatesAsset() public {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);
        assertEq(address(thunderLoan.getAssetFromToken(tokenA)), address(assetToken));
    }

    function testRevertIfDepositingNothing() public {
        tokenA.mint(liquidityProvider, AMOUNT);
        tokenA.approve(address(thunderLoan), AMOUNT);
        vm.expectRevert(ThunderLoan.ThunderLoan__CantBeZero.selector);
        thunderLoan.deposit(tokenA, 0);
    }

    function testCantDepositUnapprovedTokens() public {
        tokenA.mint(liquidityProvider, AMOUNT);
        tokenA.approve(address(thunderLoan), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ThunderLoan.ThunderLoan__NotAllowedToken.selector, address(tokenA)));
        thunderLoan.deposit(tokenA, AMOUNT);
    }

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    function testDepositMintsAssetAndUpdatesBalance() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);
        assertEq(tokenA.balanceOf(address(asset)), AMOUNT);
        assertEq(asset.balanceOf(liquidityProvider), AMOUNT);
    }

    modifier hasDeposits(address depositor) {
        vm.startPrank(depositor);
        tokenA.mint(depositor, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testRedeem() public setAllowedToken hasDeposits(liquidityProvider) hasDeposits(liquidityProvider2) {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken  = thunderLoan.getAssetFromToken(tokenA);

        uint256 expectedAmountUnderlying = (DEPOSIT_AMOUNT * assetToken.getExchangeRate()) / assetToken.EXCHANGE_RATE_PRECISION();

        vm.prank(liquidityProvider);
        vm.expectEmit();
        emit Redeemed(address(liquidityProvider), tokenA, DEPOSIT_AMOUNT, expectedAmountUnderlying);
        thunderLoan.redeem(tokenA, type(uint256).max);
    }

    function testRedeemRevertsIfAmountIsZero() public setAllowedToken hasDeposits(liquidityProvider) hasDeposits(liquidityProvider2) {
        vm.prank(liquidityProvider);
        vm.expectRevert(ThunderLoan.ThunderLoan__CantBeZero.selector);
        thunderLoan.redeem(tokenA, 0);
    }

    function testRedeemRevertsIfTokenNotAllowed() public setAllowedToken hasDeposits(liquidityProvider) hasDeposits(liquidityProvider2) {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, false);

        vm.prank(liquidityProvider);
        vm.expectPartialRevert(ThunderLoan.ThunderLoan__NotAllowedToken.selector);
        thunderLoan.redeem(tokenA, type(uint256).max);
    }

    function testFlashLoan() public setAllowedToken hasDeposits(liquidityProvider) {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        assertEq(mockFlashLoanReceiver.getbalanceDuring(), amountToBorrow + AMOUNT);
        assertEq(mockFlashLoanReceiver.getBalanceAfter(), AMOUNT - calculatedFee);
    }

    function testFlashLoanRevertsIfNotEnoughTokenBalance() public setAllowedToken hasDeposits(liquidityProvider) {
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        vm.expectPartialRevert(ThunderLoan.ThunderLoan__NotEnoughTokenBalance.selector);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, 2 * DEPOSIT_AMOUNT, "");
        vm.stopPrank();
    }

    function testFlashLoanRevertsIfReveiverIsNotContract() public setAllowedToken hasDeposits(liquidityProvider) {
        address eoa;
        (eoa, ) = makeAddrAndKey("eoa");
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        vm.expectPartialRevert(ThunderLoan.ThunderLoan__CallerIsNotContract.selector);
        thunderLoan.flashloan(address(eoa), tokenA, DEPOSIT_AMOUNT, "");
        vm.stopPrank();
    }

    function testFlashLoanRevertsIfNotPaidBack() public setAllowedToken hasDeposits(liquidityProvider) {
        uint256 amountToBorrow = AMOUNT * 10;

        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        vm.expectPartialRevert(ThunderLoan.ThunderLoan__NotPaidBack.selector);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "DO NOT REPAY");
        vm.stopPrank();
    }

    function testRepayRevertsIfNotCurrentlyFlashLoaing() public setAllowedToken hasDeposits(liquidityProvider) {
        uint256 amountToBorrow = AMOUNT;
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.expectRevert(ThunderLoan.ThunderLoan__NotCurrentlyFlashLoaning.selector);
        thunderLoan.repay(tokenA, 0);
        vm.stopPrank();
    }

    function testUpdateFlashLoanFee() public {
        uint256 expectedFee = thunderLoan.getFee() - 1;
        vm.prank(thunderLoan.owner());
        thunderLoan.updateFlashLoanFee(expectedFee);

        assertEq(expectedFee, thunderLoan.getFee());
    }

    function testUpdateFlashLoanFeeRevertsIfBadFee() public {
        uint256 badFee = thunderLoan.getFeePrecision() + 1;
        vm.prank(thunderLoan.owner());
        vm.expectRevert(ThunderLoan.ThunderLoan__BadNewFee.selector);
        thunderLoan.updateFlashLoanFee(badFee);
    }

    function testIsCurrentlyFlashLoaning() public view {
        assertEq(false, thunderLoan.isCurrentlyFlashLoaning(tokenA));
    }

    function testAuthorizeUpgrade() public {
        ThunderLoanUpgraded thunderLoanUpgraded = new ThunderLoanUpgraded();
        thunderLoan.upgradeTo(address(thunderLoanUpgraded));

        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address newImplementationAddress = address(uint160(uint256(vm.load(address(thunderLoan), slot))));

        assertEq(newImplementationAddress, address(thunderLoanUpgraded));
    }


}