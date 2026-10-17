// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Offsets} from "../src/Offsets.sol";

/// @dev A closed set of holders lets the test sum every balance and maintain an independent ledger.
contract OffsetsHandler is Test {
    Offsets public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Offsets token_) {
        token = token_;
        actors = [makeAddr("holder 0"), makeAddr("holder 1"), makeAddr("holder 2"), makeAddr("holder 3")];
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        amount = bound(amount, 0, approved < available ? approved : available);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] = approved - amount;
        }
    }

    /// @dev Make revocation and the finite/infinite boundary common in random sequences.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 kind) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[4] memory amounts = [uint256(0), type(uint256).max, type(uint256).max - 1, expectedBalance[owner]];
        uint256 amount = amounts[kind % amounts.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    /// @dev Always exercise a positive delegated transfer, even when the chosen actor is empty.
    function approveAndSpendBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, bool infinite) external {
        uint256 ownerIndex = ownerSeed % actors.length;
        while (expectedBalance[actors[ownerIndex]] == 0) {
            ownerIndex = (ownerIndex + 1) % actors.length;
        }
        address owner = actors[ownerIndex];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[owner];
        uint256 approved = infinite ? type(uint256).max : amount;

        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        expectedAllowance[owner][spender] = infinite ? type(uint256).max : 0;
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost updates: the global ledger checks every balance and allowance after rejection.
    }

    function rejectExcessAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 approved) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approved = bound(approved, 0, expectedBalance[owner]);
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approved + 1);
    }

    /// @dev Enough finite allowance, but too few tokens: an attempted allowance debit must roll back.
    function rejectUnfundedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 excess) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - 1 - balance);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        if (delegated) {
            vm.prank(owner);
            assertTrue(token.approve(spender, amount));
            expectedAllowance[owner][spender] = amount;
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    /// @dev A transfer and its inverse must recover the exact state, including sub-token amounts.
    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // The net ledger change is zero, including when from == to.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract OffsetsInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Offsets private token;
    OffsetsHandler private handler;

    function setUp() public {
        token = new Offsets();
        handler = new OffsetsHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.move.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.spend.selector;
        selectors[3] = handler.approveBoundary.selector;
        selectors[4] = handler.approveAndSpendBalance.selector;
        selectors[5] = handler.rejectOverspend.selector;
        selectors[6] = handler.rejectExcessAllowance.selector;
        selectors[7] = handler.rejectUnfundedSpend.selector;
        selectors[8] = handler.rejectZeroRecipient.selector;
        selectors[9] = handler.rejectZeroSpender.selector;
        selectors[10] = handler.roundTrip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyIsConstantAndFullyAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_BalancesAndAllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    /// @dev Liveness: every holder can still move its entire balance after any generated history.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actors(i);
            uint256 balance = token.balanceOf(holder);
            vm.prank(holder);
            assertTrue(token.transfer(address(this), balance));
            assertEq(token.balanceOf(holder), 0);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Pin a nontrivial handler history; it exercises positive spends and both allowance modes.
    function test_HandlerMixedSequence() public {
        handler.move(0, 1, SUPPLY / 2);
        handler.approveBoundary(1, 2, 1);
        handler.spend(1, 2, 3, SUPPLY / 4);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), type(uint256).max);
        handler.approveBoundary(1, 2, 0);
        handler.rejectExcessAllowance(1, 2, 3, 0);
        handler.rejectUnfundedSpend(1, 2, 3, 1);
        handler.rejectOverspend(0, 0, 1);
        handler.rejectZeroRecipient(0, 2, 1, true);
        handler.rejectZeroRecipient(0, 2, 0, false);
        handler.rejectZeroSpender(0, type(uint256).max);
        handler.roundTrip(0, 3, 1);
        handler.approveAndSpendBalance(1, 2, 0, false);
        handler.approveAndSpendBalance(2, 1, 0, true);
        handler.approveBoundary(0, 1, 2);
        handler.spend(0, 1, 0, 1);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), type(uint256).max - 2);
        invariant_SupplyIsConstantAndFullyAccountedFor();
        invariant_BalancesAndAllowancesMatchIndependentLedger();
        afterInvariant();
    }
}
