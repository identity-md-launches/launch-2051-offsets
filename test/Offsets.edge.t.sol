// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Offsets} from "src/Offsets.sol";

/// @dev Complements the original deployment tests with arithmetic boundaries and authorization histories.
/// forge-config: default.fuzz.runs = 1000
contract OffsetsEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Offsets private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;
    address private otherSpender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("edge deployer");
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
        otherSpender = makeAddr("edge other spender");
        vm.prank(deployer);
        token = new Offsets();
    }

    function test_OneWeiMovesExactlyAndCanReturn() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, 1));
        _assertInitialBalances();
    }

    function test_EntireSupplyCanMoveByAllowance() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(deployer, spender), 0);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, SUPPLY));
        _assertInitialBalances();
    }

    function test_MaximumTransferRevertsWithoutOverflowOrMutation() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
        _assertInitialBalances();
    }

    function test_InfiniteAllowanceDoesNotPermitOverspending() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, type(uint256).max);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        _assertInitialBalances();
    }

    function test_MaximumMinusOneAllowanceIsFinite() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalToZeroSpenderIsRejected() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 0);
        assertEq(token.allowance(deployer, address(0)), 0);
        assertEq(token.allowance(deployer, spender), SUPPLY);
        _assertInitialBalances();
    }

    function test_OwnerUsingTransferFromStillNeedsAnAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
        _assertInitialBalances();

        vm.prank(deployer);
        assertTrue(token.approve(deployer, 1));
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_SelfTransferCannotBypassTheBalanceCheck() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(deployer, SUPPLY + 1);
        _assertInitialBalances();
    }

    function test_DelegatedSelfTransferCannotBypassTheBalanceCheck() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(deployer, deployer, SUPPLY + 1);
        assertEq(token.allowance(deployer, spender), SUPPLY + 1);
        _assertInitialBalances();
    }

    function test_EmptyHolderCannotSelfTransferOneWei() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
        _assertInitialBalances();
    }

    function test_RevokingInfiniteAllowanceStopsAnAlreadyActiveSpender() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 0);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBeReplacedWithFiniteApproval() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(deployer);
        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RefillingBalanceDoesNotRestoreSpentAllowance() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transfer(deployer, SUPPLY));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, spender), 0);
        _assertInitialBalances();
    }

    function test_InfiniteAllowanceWorksAgainAfterHolderIsRefilled() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transfer(deployer, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, SUPPLY));
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferPartitionAndRoundTripAreExact(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        vm.prank(deployer);
        Offsets singleTransfer = new Offsets();

        vm.startPrank(deployer);
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, second));
        assertTrue(singleTransfer.transfer(alice, first + second));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), singleTransfer.balanceOf(alice));
        assertEq(token.balanceOf(deployer), singleTransfer.balanceOf(deployer));
        assertEq(token.balanceOf(alice), first + second);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(alice);
        assertTrue(token.transfer(deployer, first + second));
        _assertInitialBalances();
    }

    function testFuzz_ReapprovalReplacesRemainingAllowance(uint256 approved, uint256 spent, uint256 replacement)
        public
    {
        spent = bound(spent, 0, approved < SUPPLY ? approved : SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, spent));
        assertEq(token.allowance(deployer, spender), approved == type(uint256).max ? approved : approved - spent);

        vm.startPrank(deployer);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(deployer, spender), replacement);
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), replacement);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.balanceOf(deployer), SUPPLY - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SpendersShareTheBalanceButNotAllowances(uint256 spent) public {
        spent = bound(spent, 1, SUPPLY);
        vm.startPrank(deployer);
        token.approve(spender, SUPPLY);
        token.approve(otherSpender, SUPPLY);
        vm.stopPrank();
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, spent));
        uint256 remaining = SUPPLY - spent;
        assertEq(token.allowance(deployer, spender), remaining);
        assertEq(token.allowance(deployer, otherSpender), SUPPLY);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, remaining, remaining + 1)
        );
        vm.prank(otherSpender);
        token.transferFrom(deployer, bob, remaining + 1);
        assertEq(token.allowance(deployer, otherSpender), SUPPLY);
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(deployer, bob, remaining));
        assertEq(token.allowance(deployer, otherSpender), spent);
        assertEq(token.allowance(deployer, spender), remaining);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.balanceOf(bob), remaining);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectTransferLeavesAllowanceUntouched(uint256 approved, uint256 moved) public {
        moved = bound(moved, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, moved));
        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.balanceOf(alice), moved);
        assertEq(token.balanceOf(deployer), SUPPLY - moved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_BalanceFailureRestoresFiniteAllowance(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        uint256 attempted = balance + bound(excess, 1, type(uint256).max - 1 - balance);
        vm.prank(deployer);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, attempted);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, attempted)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, attempted);
        assertEq(token.allowance(alice, spender), attempted);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ZeroReceiverFailureRestoresFiniteAllowance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, type(uint256).max - 1);
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), amount);
        assertEq(token.allowance(deployer, spender), approved);
        _assertInitialBalances();
    }

    function testFuzz_ZeroDelegatedTransferEmitsEventAndPreservesAllowance(uint256 approved) public {
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 0));
        assertEq(token.allowance(deployer, spender), approved);
        _assertInitialBalances();
    }

    function testFuzz_DelegatedSelfTransferOnlySpendsAllowance(uint256 balance, uint256 approved, uint256 spent)
        public
    {
        balance = bound(balance, 0, SUPPLY);
        approved = bound(approved, 0, type(uint256).max - 1);
        spent = bound(spent, 0, approved < balance ? approved : balance);
        vm.prank(deployer);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, alice, spent);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, spent));
        assertEq(token.allowance(alice, spender), approved - spent);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(deployer), SUPPLY - balance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalDoesNotAuthorizeSpendingAnotherOwnersFunds(uint256 approved, uint256 balance) public {
        balance = bound(balance, 1, SUPPLY);
        vm.startPrank(deployer);
        token.transfer(alice, balance);
        token.approve(spender, approved);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, balance));
        vm.prank(spender);
        token.transferFrom(alice, bob, balance);
        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _assertInitialBalances() private view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
