// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { BaseTest, ThunderLoan, ThunderLoanUpgraded } from "./BaseTest.t.sol";
import { AssetToken } from "../../src/protocol/AssetToken.sol";
import { MockFlashLoanReceiver } from "../mocks/MockFlashLoanReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AssetTokenTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address user = address(456);
    AssetToken assetToken;

    function setUp() public override {
        super.setUp();
        vm.startPrank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        assetToken  = thunderLoan.getAssetFromToken(tokenA);
        vm.stopPrank();
    }

    function testConstructorRevertsIfTokenAddressIsZero() public {
        address owner = thunderLoan.owner();
        vm.prank(owner);
        vm.expectRevert(AssetToken.AssetToken__ZeroAddress.selector);
        new AssetToken(owner, IERC20(address(0)), "", "");
    }

    function testConstructorRevertsIfThunderLoanAddressIsZero() public {
        vm.prank(thunderLoan.owner());
        vm.expectRevert(AssetToken.AssetToken__ZeroAddress.selector);
        new AssetToken(address(0), tokenA, "", "");
    }

    function testOnlyThunderLoanCanUpdateExchangeRate() public {
        uint256 newRate = assetToken.getExchangeRate() + 1;

        vm.prank(liquidityProvider);
        vm.expectRevert(AssetToken.AssetToken__onlyThunderLoan.selector);
        assetToken.updateExchangeRate(newRate);
    }

    function testExhangeRateCanOnlyIncrease() public {
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 newRate = 1;
        vm.prank(address(thunderLoan));
        vm.expectPartialRevert(AssetToken.AssetToken__ExhangeRateCanOnlyIncrease.selector);
        assetToken.updateExchangeRate(newRate);
    }

    function testGetUnderlying() public {
        vm.prank(user);
        IERC20 actualUnderlying = assetToken.getUnderlying();
        assertEq(address(tokenA), address(actualUnderlying));
    }
}
