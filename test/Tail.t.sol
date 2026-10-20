// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {IVolatilityOracle} from "../src/interfaces/IVolatilityOracle.sol";
import {MockAlgebraPool, MockPlugin} from "./mocks/MockAlgebra.sol";
import {MockBribe} from "./mocks/MockBribe.sol";
import {ConduitTestBase} from "./utils/ConduitTestBase.sol";
import {Reference} from "./utils/Reference.sol";

contract TailTest is ConduitTestBase {
    address internal constant LOW = address(0x100);
    address internal constant HIGH = address(type(uint160).max);
    address internal constant LOW2 = address(0x200);
    address internal constant HIGH2 = address(type(uint160).max - 1);
    int256 internal constant DOUBLE = 6932;

    function _usdcTail(address tail, uint256 core, uint256 tailAmount) internal returns (address pool, MockPlugin p) {
        (pool, p) = _tailPool(address(usdc), tail, 0);
        _fee(pool, address(usdc), core);
        _fee(pool, tail, tailAmount);
    }

    function test_tail_countsUpToTheFeeBribesPricedTokens() public {
        (address pool,) = _tailPool(address(usdc), LOW, 0);
        _fee(pool, address(usdc), 100e6);
        assertEq(conduit.poolValue(pool), 100e18);
        _fee(pool, LOW, 40e6);
        assertEq(conduit.poolValue(pool), 140e18);
        _fee(pool, LOW, 60e6);
        assertEq(conduit.poolValue(pool), 200e18);
        _fee(pool, LOW, 150e6);
        assertEq(conduit.poolValue(pool), 200e18);
    }

    function test_tail_coreDepositsUnlockOnlyTheRealTail() public {
        (address pool,) = _usdcTail(HIGH, 100e6, 250e6);
        assertEq(conduit.poolValue(pool), 200e18);
        _fee(pool, address(usdc), 100e6);
        assertEq(conduit.poolValue(pool), 400e18);
        _fee(pool, address(usdc), 100e6);
        assertEq(conduit.poolValue(pool), 550e18);
        _fee(pool, address(usdc), 100e6);
        assertEq(conduit.poolValue(pool), 650e18);
    }

    function test_tail_bothTokenOrders() public {
        (address low, MockPlugin pl) = _tailPool(address(usdc), LOW, DOUBLE);
        (address high, MockPlugin ph) = _tailPool(address(usdc), HIGH, DOUBLE);
        assertEq(pl.end() - pl.start(), DOUBLE * 1800);
        assertEq(ph.end() - ph.start(), -DOUBLE * 1800);
        address[2] memory pools = [low, high];
        for (uint256 i; i < 2; ++i) {
            _fee(pools[i], address(usdc), 1000e6);
            _fee(pools[i], i == 0 ? LOW : HIGH, 100e6);
        }
        assertEq(conduit.poolValue(low), conduit.poolValue(high));
        assertApproxEqRel(conduit.poolValue(low), 1200e18, 1e13);

        (address cheap,) = _tailPool(address(usdc), HIGH, -DOUBLE);
        _fee(cheap, address(usdc), 1000e6);
        _fee(cheap, HIGH, 100e6);
        assertApproxEqRel(conduit.poolValue(cheap), 1050e18, 1e13);
    }

    function test_tail_onlyFeeBribesCount() public {
        (address pool,) = _tailPool(address(usdc), LOW, 0);
        _fee(pool, address(usdc), 100e6);
        _reward(pool, LOW, 100e6);
        assertEq(conduit.poolValue(pool), 100e18);
        _reward(pool, address(usdc), 50e6);
        _fee(pool, LOW, 100e6);
        assertEq(conduit.poolValue(pool), 250e18);
    }

    function test_tail_needsExactlyOnePricedTokenInThePair() public {
        (address both, MockPlugin pb) = _tailPool(address(usdc), address(weth), 0);
        _fee(both, address(usdc), 100e6);
        vm.expectCall(address(pb), abi.encodeWithSelector(MockPlugin.getTimepoints.selector), 0);
        assertEq(conduit.poolValue(both), 100e18);

        (address neither, MockPlugin pn) = _tailPool(LOW, HIGH, 0);
        _fee(neither, address(usdc), 100e6);
        _fee(neither, LOW, 100e6);
        _fee(neither, HIGH, 100e6);
        vm.expectCall(address(pn), abi.encodeWithSelector(MockPlugin.getTimepoints.selector), 0);
        assertEq(conduit.poolValue(neither), 100e18);
    }

    function test_tail_onlyTheGaugesOwnPool() public {
        (address pool,) = _usdcTail(LOW, 100e6, 100e6);
        assertEq(conduit.poolValue(pool), 200e18);
        algebra.setPool(address(usdc), LOW, address(0xdead));
        assertEq(conduit.poolValue(pool), 100e18);
        algebra.setPool(address(usdc), LOW, address(0));
        assertEq(conduit.poolValue(pool), 100e18);
    }

    function test_tail_singleAssetGaugeHasNoPair() public {
        address pool = _pool(0, 0);
        _fees(pool).addRewardToken(address(usdc));
        _fees(pool).addRewardToken(LOW);
        _fee(pool, address(usdc), 100e6);
        _fee(pool, LOW, 100e6);
        assertEq(conduit.poolValue(pool), 100e18);
    }

    function test_tail_fewerThanTwoRewardTokens() public {
        address pool = _pool(0, 0);
        _fee(pool, address(usdc), 100e6);
        assertEq(conduit.poolValue(pool), 100e18);
        _fees(pool).addRewardToken(address(usdc));
        assertEq(conduit.poolValue(pool), 100e18);
    }

    function test_tail_needsAFreshCoreFeed() public {
        (address pool,) = _tailPool(address(weth), LOW, 0);
        _fee(pool, address(usdc), 100e6);
        _fee(pool, LOW, 1e18);
        assertEq(conduit.poolValue(pool), 200e18);
        ethFeed.set(ETH_USD, block.timestamp - 1501);
        assertEq(conduit.poolValue(pool), 100e18);
    }

    function test_tail_zeroWithoutPricedFees() public {
        (address pool, MockPlugin p) = _tailPool(address(usdc), LOW, 0);
        _fee(pool, LOW, 100e6);
        _reward(pool, address(usdc), 100e6);
        vm.expectCall(address(p), abi.encodeWithSelector(MockPlugin.getTimepoints.selector), 0);
        assertEq(conduit.poolValue(pool), 100e18);
    }

    function test_tail_readsTheLastWindow() public {
        (address pool, MockPlugin p) = _usdcTail(LOW, 100e6, 100e6);
        uint32[] memory ago = new uint32[](2);
        ago[0] = 1800;
        vm.expectCall(address(p), abi.encodeCall(IVolatilityOracle.getTimepoints, (ago)), 1);
        conduit.poolValue(pool);
    }

    function test_tail_meanTickRoundsDown() public {
        (address low, MockPlugin pl) = _usdcTail(LOW, 1000e6, 100e6);
        (address high, MockPlugin ph) = _usdcTail(HIGH, 1000e6, 100e6);
        uint256 down = 1000e18 + 99_990_000e12;
        pl.setCumulatives(0, 1799);
        ph.setCumulatives(0, -1799);
        assertEq(conduit.poolValue(low), 1100e18);
        assertEq(conduit.poolValue(high), 1100e18);
        pl.setCumulatives(0, -1799);
        ph.setCumulatives(0, 1799);
        assertEq(conduit.poolValue(low), down);
        assertEq(conduit.poolValue(high), down);
        pl.setCumulatives(0, -1800);
        assertEq(conduit.poolValue(low), down);
        pl.setCumulatives(2 ** 55 - 1, 2 ** 55 - 1 - 1800);
        assertEq(conduit.poolValue(low), down);
    }

    function test_tail_badPluginsCountZero() public {
        (address pool, MockPlugin p) = _usdcTail(LOW, 100e6, 100e6);
        assertEq(conduit.poolValue(pool), 200e18);
        for (uint8 m = uint8(MockPlugin.Mode.Reverts); m <= uint8(MockPlugin.Mode.ReturnBomb); ++m) {
            p.setMode(MockPlugin.Mode(m));
            assertEq(conduit.poolValue(pool), 100e18, vm.toString(uint256(m)));
        }
        p.setMode(MockPlugin.Mode.Normal);
        address[3] memory others = [address(0), makeAddr("no code"), address(4)];
        for (uint256 i; i < others.length; ++i) {
            MockAlgebraPool(pool).setPlugin(others[i]);
            assertEq(conduit.poolValue(pool), 100e18);
        }
        MockAlgebraPool(pool).setPlugin(address(p));
        assertEq(conduit.poolValue(pool), 200e18);
    }

    function test_tail_returnBombIsIgnored() public {
        (address pool, MockPlugin p) = _usdcTail(LOW, 100e6, 100e6);
        p.setMode(MockPlugin.Mode.ReturnBomb);
        (bool ok, bytes memory ret) =
            address(p).staticcall{gas: conduit.TWAP_GAS()}(abi.encodeCall(MockPlugin.getTimepoints, (new uint32[](2))));
        assertTrue(ok);
        assertEq(ret.length, 100_000);
        assertEq(conduit.poolValue(pool), 100e18);
    }

    function test_tail_gasBurningPluginDoesNotBlockVotes() public {
        (address pool, MockPlugin p) = _usdcTail(LOW, 100e6, 100e6);
        p.setMode(MockPlugin.Mode.BurnsGas);
        (address[] memory pools, uint256[] memory weights) = _one(pool);
        uint256 before = gasleft();
        (, uint256 newScore) = conduit.vote(pools, weights);
        assertLt(before - gasleft(), 1_000_000);
        assertEq(newScore, 100e18);
    }

    function test_tail_edgeTicksCountZero() public {
        (address pool, MockPlugin p) = _usdcTail(LOW, 100e6, 2 ** 200);
        int256 edge = conduit.TICK_EDGE();
        int256[2] memory signs = [int256(1), -1];
        for (uint256 i; i < 2; ++i) {
            p.setTick(signs[i] * (edge - 1));
            assertEq(conduit.poolValue(pool), 200e18);
            p.setTick(signs[i] * edge);
            assertEq(conduit.poolValue(pool), 100e18);
            p.setTick(signs[i] * 887_272);
            assertEq(conduit.poolValue(pool), 100e18);
        }
    }

    function test_tail_noOverflowAtBounds() public {
        uint256 core = 1e36;
        int256 edge = conduit.TICK_EDGE();
        int256[5] memory ticks = [-(edge - 1), int256(-1), 0, 1, edge - 1];
        uint256[4] memory amounts = [uint256(1), 2 ** 128 - 1, 2 ** 128, type(uint256).max];
        for (uint256 i; i < ticks.length; ++i) {
            for (uint256 j; j < amounts.length; ++j) {
                (address pool,) = _tailPool(address(usdc), LOW, ticks[i]);
                _fee(pool, address(usdc), core);
                _fee(pool, LOW, amounts[j]);
                uint256 value = conduit.poolValue(pool);
                assertGe(value, core * 1e12);
                assertLe(value, 2 * core * 1e12);
                if (ticks[i] >= 0 && j == 3) assertEq(value, 2 * core * 1e12);
            }
        }
    }

    function test_tail_ratioConstants() public {
        uint256 core = 1e39;
        for (uint256 i; i < 20; ++i) {
            (address pool,) = _tailPool(address(usdc), LOW, -int256(1 << i));
            _fee(pool, address(usdc), core);
            _fee(pool, LOW, 1 << 128);
            uint256 constant_ = (conduit.poolValue(pool) - core * 1e12) / 1e12;
            assertApproxEqRel(constant_, Reference.ratio(1 << i), 1e3, vm.toString(i));
        }
    }

    function testFuzz_tail_matchesReference(uint256 amount, int256 tick, uint256 coreAmount, bool low) public {
        amount = bound(amount, 0, 2 ** 120);
        tick = bound(tick, 1 - conduit.TICK_EDGE(), conduit.TICK_EDGE() - 1);
        coreAmount = bound(coreAmount, 1, 1e30);
        address tail = low ? LOW : HIGH;
        (address pool,) = _tailPool(address(usdc), tail, tick);
        _fee(pool, address(usdc), coreAmount);
        _fee(pool, tail, amount);
        uint256 core = coreAmount * 1e12;
        uint256 expected = Reference.tailValue(tick, amount, 1e12, 1, core);
        uint256 value = conduit.poolValue(pool);
        assertLe(value, 2 * core);
        assertApproxEqAbs(value - core, expected, expected / 1e6 + 1e12);
    }

    function testFuzz_tail_boundedOverTheWholeTickRange(uint256 amount, int256 tick, uint256 coreAmount, bool low)
        public
    {
        tick = bound(tick, 1 - conduit.TICK_EDGE(), conduit.TICK_EDGE() - 1);
        coreAmount = bound(coreAmount, 1, 1e36);
        (address tail, address other) = low ? (LOW, LOW2) : (HIGH, HIGH2);
        (address pool,) = _tailPool(address(usdc), tail, tick);
        (address half,) = _tailPool(address(usdc), other, tick);
        _fee(pool, address(usdc), coreAmount);
        _fee(pool, tail, amount);
        _fee(half, address(usdc), coreAmount);
        _fee(half, other, amount / 2);
        uint256 core = coreAmount * 1e12;
        uint256 value = conduit.poolValue(pool);
        assertGe(value, core);
        assertLe(value, 2 * core);
        assertLe(conduit.poolValue(half), value);
    }

    function test_vote_tailCountsInProposalsAndTheVoteInForce() public {
        (address a, MockPlugin p) = _usdcTail(LOW, 100e6, 100e6);
        (address[] memory pools, uint256[] memory weights) = _one(a);
        (, uint256 newScore) = conduit.vote(pools, weights);
        assertEq(newScore, 200e18);
        assertEq(conduit.currentScore(), 200e18);
        _next();

        (pools, weights) = _one(_pool(200, 0));
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.NotBetter.selector, 200e18, 200e18));
        conduit.vote(pools, weights);

        p.setTick(-DOUBLE);
        uint256 halved = conduit.currentScore();
        assertApproxEqRel(halved, 150e18, 1e13);
        (uint256 oldScore,) = conduit.vote(pools, weights);
        assertEq(oldScore, halved);
    }

    function test_currentScore_killedGaugeKeepsItsTail() public {
        (address a,) = _usdcTail(LOW, 100e6, 100e6);
        (address[] memory pools, uint256[] memory weights) = _one(a);
        conduit.vote(pools, weights);
        voter.killGauge(voter.gauges(a));
        assertEq(conduit.currentScore(), 200e18);
    }

    function test_tail_feeBribeDepositsCountOnceWithoutATail() public {
        (address pool,) = _usdcTail(LOW, 100e6, 0);
        MockBribe fees = _fees(pool);
        usdc.mint(stranger, 100e6);
        vm.startPrank(stranger);
        usdc.approve(address(fees), 100e6);
        fees.notifyRewardAmount(address(usdc), 100e6);
        vm.stopPrank();
        assertEq(conduit.poolValue(pool), 200e18);
    }
}
