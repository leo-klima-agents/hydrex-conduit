// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {IBribe} from "./interfaces/IBribe.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

/// @notice Votes with the veNFTs delegated to it for whichever allocation is expected to pay their holders most, and
/// claims their rewards as USDC for their owners. Nothing can be changed after deployment.
contract ImmutableVeTokenConduit {
    struct PricedToken {
        address token;
        address feed;
        uint256 maxAge;
    }

    /// @dev `amount * answer * mul / div` is the value of `amount` in 18-decimal USD.
    struct Oracle {
        address token;
        address feed;
        uint256 maxAge;
        uint256 mul;
        uint256 div;
    }

    struct Swap {
        address token;
        address router;
        bytes data;
    }

    struct Pool {
        address pool;
        bool alive;
        uint256 value;
        uint256 others;
        uint256 own;
    }

    struct Context {
        uint256 epoch;
        uint256 power;
        bool voted;
        Oracle[] oracles;
        uint256[] answers;
        Pool[] cache;
        uint256 cached;
    }

    address public constant TREASURY = 0x450c72de8c0079B49AcedF294a13011bd09D125B;
    uint256 public constant FEE_BPS = 100;
    uint256 public constant MAX_POOLS = 20;
    uint256 public constant MIN_GAIN = 1e18;
    uint256 public constant MAX_SLIPPAGE_BPS = 100;
    uint256 public constant SEQUENCER_GRACE = 3600;
    uint256 public constant WEEK = 604800;

    address public immutable voter;
    address public immutable veToken;
    address public immutable usdc;
    address public immutable sequencerFeed;

    address[] public approvedRouters;
    mapping(address => bool) public isApprovedRouter;
    Oracle[] public pricedTokens;

    bool private transient locked;

    event VoteAccepted(
        uint256 indexed epoch,
        address indexed proposer,
        address[] pools,
        uint256[] weights,
        uint256 oldScore,
        uint256 newScore
    );
    event Claimed(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed caller,
        address[] claimTokens,
        uint256[] claimedAmounts,
        uint256 usdcReceived,
        uint256 fee
    );

    error ZeroAddress();
    error NotAContract(address account);
    error BadConfig();
    error BadRouter(address router);
    error Duplicate(address account);
    error UnpricedToken(address token);
    error SequencerDown();
    error EpochStale();
    error NoVotingPower();
    error BadPoolCount();
    error LengthMismatch();
    error ZeroWeight();
    error ZeroVotes(address pool);
    error DeadGauge(address pool);
    error NotBetter(uint256 newScore, uint256 oldScore);
    error UnapprovedRouter(address router);
    error BadSwap(address token);
    error RewardNotSwapped(address token);
    error BelowOracleFloor(uint256 received, uint256 floor);
    error InsufficientOutput(uint256 usdcOut, uint256 minUsdcOut);
    error TokenCallFailed(address token);
    error Reentrancy();

    modifier nonReentrant() {
        if (locked) revert Reentrancy();
        locked = true;
        _;
        locked = false;
    }

    constructor(
        address voter_,
        address veToken_,
        address usdc_,
        address sequencerFeed_,
        address[] memory routers_,
        PricedToken[] memory pricedTokens_
    ) {
        if (voter_ == address(0) || veToken_ == address(0) || usdc_ == address(0) || sequencerFeed_ == address(0)) {
            revert ZeroAddress();
        }
        voter = voter_;
        veToken = veToken_;
        usdc = usdc_;
        sequencerFeed = sequencerFeed_;

        uint256 n = pricedTokens_.length;
        if (n == 0 || n > 8) revert BadConfig();
        bool hasUsdc;
        for (uint256 i; i < n; ++i) {
            PricedToken memory p = pricedTokens_[i];
            if (p.token == address(0) || p.feed == address(0)) revert ZeroAddress();
            if (p.feed.code.length == 0) revert NotAContract(p.feed);
            for (uint256 j; j < i; ++j) {
                if (pricedTokens_[j].token == p.token) revert Duplicate(p.token);
            }
            if (_answer(p.feed, p.maxAge) == 0) revert UnpricedToken(p.token);
            uint256 d = uint256(IERC20(p.token).decimals()) + IAggregatorV3(p.feed).decimals();
            pricedTokens.push(
                Oracle(p.token, p.feed, p.maxAge, d < 18 ? 10 ** (18 - d) : 1, d > 18 ? 10 ** (d - 18) : 1)
            );
            hasUsdc = hasUsdc || p.token == usdc_;
        }
        if (!hasUsdc) revert BadConfig();

        if (routers_.length == 0) revert BadConfig();
        for (uint256 i; i < routers_.length; ++i) {
            address r = routers_[i];
            if (r == address(0)) revert ZeroAddress();
            if (r.code.length == 0) revert NotAContract(r);
            if (isApprovedRouter[r] || r == voter_ || r == veToken_ || r == usdc_ || r == sequencerFeed_) {
                revert BadRouter(r);
            }
            for (uint256 j; j < n; ++j) {
                if (r == pricedTokens_[j].token || r == pricedTokens_[j].feed) revert BadRouter(r);
            }
            isApprovedRouter[r] = true;
            approvedRouters.push(r);
        }

        _checkSequencer();

        uint8[] memory actions = new uint8[](2);
        actions[0] = 3; // CLAIM_REDIRECT_APPROVAL
        actions[1] = 5; // VOTING_DELEGATE
        IVotingEscrow(veToken_).setConduitApprovalConfig(actions, "");
    }

    function vote(address[] calldata pools, uint256[] calldata weights)
        external
        nonReentrant
        returns (uint256 newScore, uint256 oldScore)
    {
        Context memory ctx = _context();
        oldScore = _currentScore(ctx);
        newScore = _proposalScore(ctx, pools, weights);
        if (newScore < oldScore + MIN_GAIN) revert NotBetter(newScore, oldScore);
        IVoter(voter).vote(pools, weights);
        emit VoteAccepted(ctx.epoch, msg.sender, pools, weights, oldScore, newScore);
    }

    function score(address[] calldata pools, uint256[] calldata weights) external view returns (uint256) {
        return _proposalScore(_context(), pools, weights);
    }

    function currentScore() external view returns (uint256) {
        return _currentScore(_context());
    }

    function poolValue(address pool) external view returns (uint256 usd) {
        return _pool(_context(), pool).value;
    }

    function claim(
        uint256 tokenId,
        address[] calldata feeAddresses,
        address[] calldata bribeAddresses,
        address[] calldata claimTokens,
        Swap[] calldata swaps,
        uint256 minUsdcOut
    ) external nonReentrant returns (uint256 usdcOut, uint256 fee) {
        address owner = IVotingEscrow(veToken).ownerOf(tokenId);
        uint256 n = claimTokens.length;
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < i; ++j) {
                if (claimTokens[j] == claimTokens[i]) revert Duplicate(claimTokens[i]);
            }
        }

        Oracle[] memory oracles;
        uint256[] memory answers;
        if (msg.sender != owner) {
            _checkSequencer();
            oracles = pricedTokens;
            answers = _answers(oracles);
            for (uint256 i; i < n; ++i) {
                _priced(oracles, answers, claimTokens[i]);
            }
        }

        uint256[] memory before = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            before[i] = IERC20(claimTokens[i]).balanceOf(address(this));
        }
        uint256 received = IERC20(usdc).balanceOf(address(this));

        if (feeAddresses.length != 0) {
            IVoter(voter)
                .claimFeesToRecipientByTokenId(
                    feeAddresses, _repeat(claimTokens, feeAddresses.length), tokenId, address(this)
                );
        }
        if (bribeAddresses.length != 0) {
            IVoter(voter)
                .claimBribesToRecipientByTokenId(
                    bribeAddresses, _repeat(claimTokens, bribeAddresses.length), tokenId, address(this)
                );
        }

        uint256[] memory claimed = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            claimed[i] = IERC20(claimTokens[i]).balanceOf(address(this)) - before[i];
        }

        for (uint256 i; i < swaps.length; ++i) {
            Swap calldata s = swaps[i];
            if (!isApprovedRouter[s.router]) revert UnapprovedRouter(s.router);
            uint256 k;
            while (k < n && claimTokens[k] != s.token) ++k;
            if (k == n || s.token == usdc) revert BadSwap(s.token);
            for (uint256 j; j < i; ++j) {
                if (swaps[j].token == s.token) revert BadSwap(s.token);
            }
            if (claimed[k] == 0) continue;
            _safe(s.token, abi.encodeCall(IERC20.approve, (s.router, 0)));
            _safe(s.token, abi.encodeCall(IERC20.approve, (s.router, claimed[k])));
            (bool ok, bytes memory ret) = s.router.call(s.data);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
            _safe(s.token, abi.encodeCall(IERC20.approve, (s.router, 0)));
        }

        for (uint256 i; i < n; ++i) {
            if (claimTokens[i] != usdc && IERC20(claimTokens[i]).balanceOf(address(this)) != before[i]) {
                revert RewardNotSwapped(claimTokens[i]);
            }
        }
        received = IERC20(usdc).balanceOf(address(this)) - received;

        if (msg.sender != owner) {
            uint256 floor = _floor(oracles, answers, claimTokens, claimed);
            if (received < floor) revert BelowOracleFloor(received, floor);
        }

        fee = _fee(received, FEE_BPS);
        usdcOut = received - fee;
        if (usdcOut < minUsdcOut) revert InsufficientOutput(usdcOut, minUsdcOut);
        if (fee != 0) _safe(usdc, abi.encodeCall(IERC20.transfer, (TREASURY, fee)));
        if (usdcOut != 0) _safe(usdc, abi.encodeCall(IERC20.transfer, (owner, usdcOut)));
        emit Claimed(tokenId, owner, msg.sender, claimTokens, claimed, received, fee);
    }

    function claimFloor(address[] calldata tokens, uint256[] calldata amounts) external view returns (uint256) {
        if (tokens.length != amounts.length) revert LengthMismatch();
        _checkSequencer();
        Oracle[] memory oracles = pricedTokens;
        return _floor(oracles, _answers(oracles), tokens, amounts);
    }

    function _context() private view returns (Context memory ctx) {
        _checkSequencer();
        ctx.epoch = IVoter(voter)._epochTimestamp();
        if (ctx.epoch != block.timestamp - block.timestamp % WEEK) revert EpochStale();
        ctx.power = IVotingEscrow(veToken).getPastVotes(address(this), ctx.epoch);
        if (ctx.power == 0) revert NoVotingPower();
        ctx.voted = IVoter(voter).lastVoted(address(this)) >= ctx.epoch;
        ctx.oracles = pricedTokens;
        ctx.answers = _answers(ctx.oracles);
        ctx.cache = new Pool[](2 * MAX_POOLS);
    }

    function _currentScore(Context memory ctx) private view returns (uint256 s) {
        if (!ctx.voted) return 0;
        uint256 n = IVoter(voter).poolVoteLength(address(this));
        for (uint256 i; i < n; ++i) {
            Pool memory p = _pool(ctx, IVoter(voter).poolVote(address(this), i));
            if (p.alive) s += _share(p.value, p.others, p.own);
        }
    }

    function _proposalScore(Context memory ctx, address[] calldata pools, uint256[] calldata weights)
        private
        view
        returns (uint256 s)
    {
        uint256 n = pools.length;
        if (n == 0 || n > MAX_POOLS) revert BadPoolCount();
        if (n != weights.length) revert LengthMismatch();
        uint256 total;
        for (uint256 i; i < n; ++i) {
            if (weights[i] == 0) revert ZeroWeight();
            for (uint256 j; j < i; ++j) {
                if (pools[j] == pools[i]) revert Duplicate(pools[i]);
            }
            total += weights[i];
        }
        for (uint256 i; i < n; ++i) {
            uint256 x = weights[i] * ctx.power / total;
            if (x == 0) revert ZeroVotes(pools[i]);
            Pool memory p = _pool(ctx, pools[i]);
            if (!p.alive) revert DeadGauge(pools[i]);
            s += _share(p.value, p.others, x);
        }
    }

    function _pool(Context memory ctx, address pool) private view returns (Pool memory p) {
        for (uint256 i; i < ctx.cached; ++i) {
            if (ctx.cache[i].pool == pool) return ctx.cache[i];
        }
        IVoter v = IVoter(voter);
        address gauge = v.gauges(pool);
        p.pool = pool;
        p.alive = v.isAlive(gauge);
        if (p.alive) {
            p.value = _bribeValue(ctx, v.external_bribes(gauge)) + _bribeValue(ctx, v.internal_bribes(gauge));
            if (ctx.voted) p.own = v.votes(address(this), pool);
            p.others = v.weights(pool) - p.own;
        }
        if (ctx.cached < ctx.cache.length) ctx.cache[ctx.cached++] = p;
    }

    function _bribeValue(Context memory ctx, address bribe) private view returns (uint256 usd) {
        for (uint256 i; i < ctx.oracles.length; ++i) {
            if (ctx.answers[i] == 0) continue;
            (, uint256 amount,) = IBribe(bribe).rewardData(ctx.oracles[i].token, ctx.epoch);
            usd += _usd(ctx.oracles[i], ctx.answers[i], amount);
        }
    }

    /// @dev floor(b * x / (others + x)) without overflowing b * x.
    function _share(uint256 b, uint256 others, uint256 x) private pure returns (uint256) {
        uint256 d = others + x;
        // forge-lint: disable-next-line(divide-before-multiply)
        return b / d * x + b % d * x / d;
    }

    /// @dev The claimed USDC, plus the other tokens' Chainlink value in USDC less `MAX_SLIPPAGE_BPS`.
    function _floor(
        Oracle[] memory oracles,
        uint256[] memory answers,
        address[] calldata tokens,
        uint256[] memory amounts
    ) private view returns (uint256 floor) {
        uint256 usd;
        for (uint256 i; i < tokens.length; ++i) {
            uint256 j = _priced(oracles, answers, tokens[i]);
            if (tokens[i] == usdc) floor += amounts[i];
            else usd += _usd(oracles[j], answers[j], amounts[i]);
        }
        uint256 u = _priced(oracles, answers, usdc);
        floor += usd * (10_000 - MAX_SLIPPAGE_BPS) * oracles[u].div / (10_000 * answers[u] * oracles[u].mul);
    }

    function _priced(Oracle[] memory oracles, uint256[] memory answers, address token)
        private
        pure
        returns (uint256 i)
    {
        while (i < oracles.length && oracles[i].token != token) ++i;
        if (i == oracles.length || answers[i] == 0) revert UnpricedToken(token);
    }

    function _usd(Oracle memory o, uint256 answer, uint256 amount) private pure returns (uint256) {
        return amount * answer * o.mul / o.div;
    }

    function _answers(Oracle[] memory oracles) private view returns (uint256[] memory answers) {
        answers = new uint256[](oracles.length);
        for (uint256 i; i < oracles.length; ++i) {
            answers[i] = _answer(oracles[i].feed, oracles[i].maxAge);
        }
    }

    /// @dev The feed's answer, or 0 if the call fails or the answer is stale or not positive.
    function _answer(address feed, uint256 maxAge) private view returns (uint256) {
        (bool ok, bytes memory ret) = feed.staticcall(abi.encodeCall(IAggregatorV3.latestRoundData, ()));
        if (!ok || ret.length != 160) return 0;
        (, int256 answer,, uint256 updatedAt,) = abi.decode(ret, (uint256, int256, uint256, uint256, uint256));
        if (answer <= 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > maxAge) return 0;
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(answer);
    }

    function _checkSequencer() private view {
        (, int256 answer, uint256 startedAt,,) = IAggregatorV3(sequencerFeed).latestRoundData();
        if (answer != 0 || block.timestamp - startedAt <= SEQUENCER_GRACE) revert SequencerDown();
    }

    function _repeat(address[] calldata tokens, uint256 n) private pure returns (address[][] memory r) {
        address[] memory t = tokens;
        r = new address[][](n);
        for (uint256 i; i < n; ++i) {
            r[i] = t;
        }
    }

    function _safe(address token, bytes memory data) private {
        (bool ok, bytes memory ret) = token.call(data);
        if (!ok || (ret.length == 0 ? token.code.length == 0 : !abi.decode(ret, (bool)))) {
            revert TokenCallFailed(token);
        }
    }

    function _fee(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return amount * bps / 10_000;
    }
}
