// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BabyIMD} from "../src/BabyIMD.sol";

contract BabyIMDTest is Test {
    BabyIMD internal t;
    address internal constant FACTORY = address(0xFAC7);
    address internal constant DEV = 0x8Ad18E99F4C8d8406f9Ba8899CF308000518A981;
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant SUPPLY = 1_000_000_000e18;

    function setUp() public {
        vm.prank(FACTORY);
        t = new BabyIMD();
    }

    function test_metadata() public view {
        assertEq(t.name(), "babyIMD");
        assertEq(t.symbol(), "bIMD");
        assertEq(t.decimals(), 18);
        assertEq(t.FACTORY(), FACTORY);
        assertEq(t.DEV(), DEV);
        assertEq(t.DEAD(), DEAD);
        assertEq(t.DEV_SHARE(), 50_000_000e18);
    }

    function test_wholeSupplyToDeployer() public view {
        assertEq(t.totalSupply(), SUPPLY);
        assertEq(t.TOTAL_SUPPLY(), SUPPLY);
        assertEq(t.balanceOf(FACTORY), SUPPLY);
    }

    function test_noPrivilegedSelectors() public {
        bytes[] memory calls = new bytes[](11);
        calls[0] = abi.encodeWithSignature("owner()");
        calls[1] = abi.encodeWithSignature("mint(address,uint256)", FACTORY, 1);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", FACTORY, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("transferOwnership(address)", FACTORY);
        calls[6] = abi.encodeWithSignature("renounceOwnership()");
        calls[7] = abi.encodeWithSignature("setFee(uint256)", 1);
        calls[8] = abi.encodeWithSignature("setDev(address)", FACTORY);
        calls[9] = abi.encodeWithSignature("setFactory(address)", FACTORY);
        calls[10] = abi.encodeWithSignature("blacklist(address)", DEV);
        address[3] memory callers = [FACTORY, DEV, address(this)];
        for (uint256 j; j < callers.length; j++) {
            for (uint256 i; i < calls.length; i++) {
                vm.prank(callers[j]);
                (bool ok,) = address(t).call(calls[i]);
                assertFalse(ok);
            }
        }
        assertEq(t.totalSupply(), SUPPLY);
    }

    /// The launch remainder: 55% of the supply plus pool rounding dust, sent by the factory to DEV.
    function test_launchRemainderSplitOnArrival() public {
        uint256 remainder = 550_000_001_000_000_000_000_001_955;
        vm.expectEmit(true, true, false, true, address(t));
        emit IERC20.Transfer(FACTORY, DEAD, remainder - 50_000_000e18);
        vm.expectEmit(true, true, false, true, address(t));
        emit IERC20.Transfer(FACTORY, DEV, 50_000_000e18);
        vm.prank(FACTORY);
        assertTrue(t.transfer(DEV, remainder));
        assertEq(t.balanceOf(DEV), 50_000_000e18, "dev keeps exactly 5%");
        assertEq(t.balanceOf(DEAD), remainder - 50_000_000e18, "rest burned, dust included");
        assertEq(t.balanceOf(FACTORY), SUPPLY - remainder);
        assertEq(t.totalSupply(), SUPPLY);
    }

    function test_smallFactoryTransferToDevSplitsElevenths() public {
        vm.prank(FACTORY);
        t.transfer(DEV, 11e18);
        assertEq(t.balanceOf(DEV), 1e18);
        assertEq(t.balanceOf(DEAD), 10e18);
        vm.prank(FACTORY);
        t.transfer(DEV, 10);
        assertEq(t.balanceOf(DEV), 1e18, "10 wei: 1/11 rounds down to 0 for dev");
        assertEq(t.balanceOf(DEAD), 10e18 + 10);
        vm.prank(FACTORY);
        t.transfer(DEV, 0);
        assertEq(t.balanceOf(FACTORY), SUPPLY - 11e18 - 10);
    }

    /// Any amount from the factory to DEV: DEV gets min(amount / 11, DEV_SHARE), DEAD the rest, nothing lost.
    function testFuzz_factoryToDevSplit(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(FACTORY);
        assertTrue(t.transfer(DEV, amount));
        uint256 kept = amount / 11 > 50_000_000e18 ? 50_000_000e18 : amount / 11;
        assertEq(t.balanceOf(DEV), kept);
        assertEq(t.balanceOf(DEAD), amount - kept);
        assertEq(t.balanceOf(FACTORY), SUPPLY - amount);
        assertEq(t.totalSupply(), SUPPLY);
    }

    /// The factory to anyone but DEV: exact.
    function testFuzz_factoryToOthersExact(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != FACTORY && to != DEV);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(FACTORY);
        assertTrue(t.transfer(to, amount));
        assertEq(t.balanceOf(to), amount);
        assertEq(t.balanceOf(FACTORY), SUPPLY - amount);
    }

    /// Holders, DEV included, move exact amounts to anyone, DEV included.
    function testFuzz_holderTransfersExact(address holder, address to, uint256 amount) public {
        vm.assume(holder != address(0) && holder != FACTORY && holder != DEV && holder != DEAD);
        vm.assume(to != address(0) && to != FACTORY && to != holder);
        uint256 funded = 100_000_000e18;
        vm.prank(FACTORY);
        t.transfer(holder, funded);
        amount = bound(amount, 0, funded);
        uint256 toBefore = t.balanceOf(to);
        vm.prank(holder);
        assertTrue(t.transfer(to, amount));
        assertEq(t.balanceOf(to), toBefore + amount);
        assertEq(t.balanceOf(holder), funded - amount);
    }

    function testFuzz_holderToDevExact(uint256 amount) public {
        address holder = address(0xB0B);
        vm.prank(FACTORY);
        t.transfer(holder, 200_000_000e18);
        amount = bound(amount, 0, 200_000_000e18);
        vm.prank(holder);
        t.transfer(DEV, amount);
        assertEq(t.balanceOf(DEV), amount);
        assertEq(t.balanceOf(DEAD), 0);
    }

    function test_devTransfersExact() public {
        vm.prank(FACTORY);
        t.transfer(DEV, 550_000_000e18);
        address bob = address(0xB0B);
        vm.prank(DEV);
        t.transfer(bob, 20_000_000e18);
        assertEq(t.balanceOf(bob), 20_000_000e18);
        assertEq(t.balanceOf(DEV), 30_000_000e18);
        vm.prank(bob);
        t.transfer(DEV, 5_000_000e18);
        assertEq(t.balanceOf(DEV), 35_000_000e18);
    }

    function testFuzz_transferFromMovesExactAmount(address spender, address to, uint256 amount) public {
        vm.assume(spender != address(0) && to != address(0) && to != FACTORY);
        address holder = address(0xA11CE);
        vm.prank(FACTORY);
        t.transfer(holder, SUPPLY / 2);
        amount = bound(amount, 0, SUPPLY / 2);
        vm.prank(holder);
        t.approve(spender, amount);
        uint256 toBefore = t.balanceOf(to);
        vm.prank(spender);
        assertTrue(t.transferFrom(holder, to, amount));
        assertEq(t.balanceOf(to), to == holder ? SUPPLY / 2 : toBefore + amount);
        assertEq(t.allowance(holder, spender), 0);
    }

    function test_transferToDeadKeepsTotalSupply() public {
        vm.prank(FACTORY);
        t.transfer(DEAD, 500_000_000e18);
        assertEq(t.balanceOf(DEAD), 500_000_000e18);
        assertEq(t.totalSupply(), SUPPLY);
    }
}
