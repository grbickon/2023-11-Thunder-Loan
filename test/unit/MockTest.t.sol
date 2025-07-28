// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { BaseTest, ThunderLoan, ThunderLoanUpgraded } from "./BaseTest.t.sol";
import { AssetToken } from "../../src/protocol/AssetToken.sol";
import { MockFlashLoanReceiver } from "../mocks/MockFlashLoanReceiver.sol";
import { MockPoolFactory } from "../mocks/MockPoolFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockFlashLoanReceiverTest is BaseTest {
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

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    modifier hasDeposits(address depositor) {
        vm.startPrank(depositor);
        tokenA.mint(depositor, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testExecuteOperationRevertsIfInitiatedByNonOwner() public setAllowedToken hasDeposits(liquidityProvider) {
        uint256 amountToBorrow = AMOUNT * 10;
        vm.prank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);

        address nonOwner = liquidityProvider;
        vm.prank(nonOwner);
        vm.expectRevert(MockFlashLoanReceiver.MockFlashLoanReceiver__onlyOwner.selector);
        mockFlashLoanReceiver.executeOperation(address(tokenA), amountToBorrow, 1, nonOwner, "");
    }

    function testExecuteOperationRevertsIfNotCalledByThunderLoan() public setAllowedToken hasDeposits(liquidityProvider) {
        uint256 amountToBorrow = AMOUNT * 10;
        vm.prank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);

        address notThundeLoan = liquidityProvider;
        vm.prank(notThundeLoan);
        vm.expectRevert(MockFlashLoanReceiver.MockFlashLoanReceiver__onlyThunderLoan.selector);
        mockFlashLoanReceiver.executeOperation(address(tokenA), amountToBorrow, 1, user, "");
    }
}
contract MockPoolFactoryTest is BaseTest {
    function testCreatePoolRevertsIfPoolAlreadyExists() public {
        vm.expectPartialRevert(MockPoolFactory.PoolFactory__PoolAlreadyExists.selector);
        mockPoolFactory.createPool(address(tokenA));
    }
}