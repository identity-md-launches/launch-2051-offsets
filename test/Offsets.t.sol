// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Offsets} from "../src/Offsets.sol";
import {TokenDeployer} from "./helpers/TokenDeployer.sol";

contract OffsetsTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    Offsets private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new Offsets();
    }

    function test_MetadataAndInitialAllocation() public view {
        assertEq(token.name(), "Offsets");
        assertEq(token.symbol(), "OFFSETS");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_ConstructorEmitsOneMintEvent() public {
        vm.recordLogs();
        vm.prank(alice);
        Offsets fresh = new Offsets();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(alice), SUPPLY);
    }

    function test_FactoryReceivesSupplyInsteadOfTransactionOrigin() public {
        TokenDeployer factory = new TokenDeployer();
        vm.prank(alice, alice);
        Offsets fresh = factory.deploy();

        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
    }

    function test_Create2DeploymentNeedsNoConfiguration() public {
        TokenDeployer factory = new TokenDeployer();
        bytes32 salt = keccak256("offsets deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Offsets).creationCode))
                    )
                )
            )
        );
        Offsets fresh = factory.deployDeterministic(salt);

        assertEq(address(fresh), predicted);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_LaunchDistributionAndClaimTransfersAreExact() public {
        TokenDeployer factory = new TokenDeployer();
        Offsets fresh = factory.deploy();
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address recipient = makeAddr("launch remainder recipient");

        assertTrue(factory.move(fresh, distributor, SUPPLY / 10));
        assertTrue(factory.move(fresh, poolManager, SUPPLY * 8 / 10));
        assertTrue(factory.move(fresh, recipient, SUPPLY / 10));
        assertEq(fresh.balanceOf(address(factory)), 0);
        assertEq(fresh.balanceOf(distributor), SUPPLY / 10);
        assertEq(fresh.balanceOf(poolManager), SUPPLY * 8 / 10);
        assertEq(fresh.balanceOf(recipient), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(fresh.transfer(alice, SUPPLY / 10));
        assertEq(fresh.balanceOf(distributor), 0);
        assertEq(fresh.balanceOf(alice), SUPPLY / 10);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_TransferReturnsTrueAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 123 ether);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 123 ether));

        assertEq(token.balanceOf(deployer), SUPPLY - 123 ether);
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanMoveAndReturn() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroRevertsWithoutBurning() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferToZeroAlsoReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 0);
    }

    function test_TransferMoreThanBalanceRevertsAtomically() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveReturnsTrueAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 50 ether);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(deployer, spender), 50 ether);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_ApprovalCanBeReplacedAndRevoked() public {
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, 100 ether));
        assertTrue(token.approve(spender, 40 ether));
        assertEq(token.allowance(deployer, spender), 40 ether);
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApprovalDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_TransferFromConsumesAllowanceAndEmitsTransfer() public {
        vm.prank(deployer);
        token.approve(spender, 50 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 20 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 20 ether));

        assertEq(token.allowance(deployer, spender), 30 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 20 ether);
        assertEq(token.balanceOf(alice), 20 ether);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_TransferFromExactAllowanceExhaustsIt() public {
        vm.prank(deployer);
        token.approve(spender, 5 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 5 ether));
        assertEq(token.allowance(deployer, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(alice), 5 ether);
    }

    function test_InfiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 2 ether));
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 2 ether);
    }

    function test_TransferFromWithoutApprovalReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApprovalIsSpecificToSpender() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, spender), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromWithInsufficientBalanceRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1 ether);
        assertEq(token.allowance(alice, spender), 100 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToZeroRestoresAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 1 ether);
        assertEq(token.allowance(deployer, spender), 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromDoesNotRequireApproval() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferFromSpendsAllowanceWithoutChangingBalance() public {
        vm.prank(deployer);
        token.approve(spender, 1 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 1 ether));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DeployerCannotSpendHolderFundsWithoutApproval() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 100 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_NoMintBurnOrAdminEntryPoints() public {
        bytes[] memory calls = new bytes[](18);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[5] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[6] = abi.encodeWithSignature("initialize(address)", bob);
        calls[7] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[9] = abi.encodeWithSignature("setOwner(address)", bob);
        calls[10] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[11] = abi.encodeWithSignature("pause()");
        calls[12] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[13] = abi.encodeWithSignature("freeze(address)", alice);
        calls[14] = abi.encodeWithSignature("seize(address)", alice);
        calls[15] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        calls[16] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[17] = abi.encodeWithSignature("owner()");

        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        address[2] memory callers = [deployer, bob];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < calls.length; ++j) {
                vm.prank(callers[i]);
                (bool success,) = address(token).call(calls[j]);
                assertFalse(success);
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(alice), 10 ether);
                assertEq(token.balanceOf(bob), 0);
            }
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_RuntimeContainsNoForbiddenOpcodes() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 opcode = uint8(code[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
            }
        }
    }

    function testFuzz_TransfersConserveSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != deployer);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverspendingReverts(uint256 excess) public {
        excess = bound(excess, 1, type(uint256).max - SUPPLY);
        uint256 amount = SUPPLY + excess;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromTracksAllowance(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, spent));
        assertEq(token.allowance(deployer, spender), approved - spent);
        assertEq(token.balanceOf(deployer), SUPPLY - spent);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ExceedingAllowanceRevertsAtomically(uint256 approved) public {
        approved = bound(approved, 0, SUPPLY - 1);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, approved + 1);
        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
