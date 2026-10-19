// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {IBribe} from "./interfaces/IBribe.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

contract ImmutableVeTokenConduit {
    struct PricedToken {
        address token;
        address feed;
        uint256 maxAge;
    }

    struct Oracle {
        address token;
        address feed;
        uint256 maxAge;
        uint256 mul;
        uint256 div;
    }

    struct Pool {
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
    }

    address public constant TREASURY = 0x450c72de8c0079B49AcedF294a13011bd09D125B;
    uint256 public constant FEE_BPS = 100;
    uint256 public constant MAX_POOLS = 20;
    uint256 public constant MIN_GAIN = 1e18;
    uint256 public constant SEQUENCER_GRACE = 3600;
    uint256 private constant WEEK = 604800;
    uint256 private constant MAX_PRICED_TOKENS = 4;
    uint8 private constant CLAIM_REDIRECT_APPROVAL = 3;
    uint8 private constant VOTING_DELEGATE = 5;

    address public immutable voter;
    address public immutable veToken;
    address public immutable sequencerFeed;

    Oracle[] public pricedTokens;
    mapping(uint256 tokenId => uint256 blockNumber) public lastClaimBlock;

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
        address[] tokens,
        uint256[] amounts,
        uint256[] fees,
        uint256 previousClaimBlock
    );

    error ZeroAddress();
    error BadPricedTokenCount();
    error Duplicate(address account);
    error NoRewardContracts();
    error BadFeed(address feed);
    error SequencerDown();
    error EpochStale();
    error NoVotingPower();
    error BadPoolCount();
    error LengthMismatch();
    error ZeroWeight();
    error ZeroVotes(address pool);
    error DeadGauge(address pool);
    error NotBetter(uint256 oldScore, uint256 newScore);
    error TokenCallFailed(address token);
    error Reentrancy();

    modifier nonReentrant() {
        if (locked) revert Reentrancy();
        locked = true;
        _;
        locked = false;
    }

    constructor(address voter_, address veToken_, address sequencerFeed_, PricedToken[] memory pricedTokens_) {
        if (voter_ == address(0) || veToken_ == address(0) || sequencerFeed_ == address(0)) revert ZeroAddress();
        voter = voter_;
        veToken = veToken_;
        sequencerFeed = sequencerFeed_;

        uint256 n = pricedTokens_.length;
        if (n == 0 || n > MAX_PRICED_TOKENS) revert BadPricedTokenCount();
        for (uint256 i; i < n; ++i) {
            PricedToken memory p = pricedTokens_[i];
            for (uint256 j; j < i; ++j) {
                if (pricedTokens_[j].token == p.token) revert Duplicate(p.token);
            }
            if (_answer(p.feed, p.maxAge) == 0) revert BadFeed(p.feed);
            uint256 d = uint256(IERC20(p.token).decimals()) + IAggregatorV3(p.feed).decimals();
            pricedTokens.push(
                Oracle(p.token, p.feed, p.maxAge, d < 18 ? 10 ** (18 - d) : 1, d > 18 ? 10 ** (d - 18) : 1)
            );
        }
        _checkSequencer();

        uint8[] memory actions = new uint8[](2);
        actions[0] = CLAIM_REDIRECT_APPROVAL;
        actions[1] = VOTING_DELEGATE;
        IVotingEscrow(veToken_).setConduitApprovalConfig(actions, "");
    }

    function vote(address[] calldata pools, uint256[] calldata weights)
        external
        nonReentrant
        returns (uint256 oldScore, uint256 newScore)
    {
        Context memory ctx = _context();
        newScore = _proposalScore(ctx, pools, weights);
        oldScore = _currentScore(ctx);
        if (newScore < oldScore + MIN_GAIN) revert NotBetter(oldScore, newScore);
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
        address[] calldata tokens
    ) external nonReentrant returns (uint256[] memory amounts) {
        if (feeAddresses.length == 0 && bribeAddresses.length == 0) {
            revert NoRewardContracts();
        }
        address owner = IVotingEscrow(veToken).ownerOf(tokenId);
        uint256 n = tokens.length;
        uint256[] memory before = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            before[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        if (feeAddresses.length != 0) {
            IVoter(voter)
                .claimFeesToRecipientByTokenId(
                    feeAddresses, _repeat(tokens, feeAddresses.length), tokenId, address(this)
                );
        }
        if (bribeAddresses.length != 0) {
            IVoter(voter)
                .claimBribesToRecipientByTokenId(
                    bribeAddresses, _repeat(tokens, bribeAddresses.length), tokenId, address(this)
                );
        }

        amounts = new uint256[](n);
        uint256[] memory fees = new uint256[](n);
        bool received;
        for (uint256 i; i < n; ++i) {
            amounts[i] = IERC20(tokens[i]).balanceOf(address(this)) - before[i];
            if (amounts[i] != 0) received = true;
            fees[i] = amounts[i] * FEE_BPS / 10_000;
            if (fees[i] != 0) _transfer(tokens[i], TREASURY, fees[i]);
            if (amounts[i] != fees[i]) _transfer(tokens[i], owner, amounts[i] - fees[i]);
        }
        uint256 previous = lastClaimBlock[tokenId];
        if (received) lastClaimBlock[tokenId] = block.number;
        emit Claimed(tokenId, owner, msg.sender, tokens, amounts, fees, previous);
    }

    function _context() private view returns (Context memory ctx) {
        _checkSequencer();
        ctx.epoch = IVoter(voter)._epochTimestamp();
        if (ctx.epoch != block.timestamp - block.timestamp % WEEK) revert EpochStale();
        ctx.power = IVotingEscrow(veToken).getPastVotes(address(this), ctx.epoch);
        if (ctx.power == 0) revert NoVotingPower();
        ctx.voted = IVoter(voter).lastVoted(address(this)) >= ctx.epoch;
        ctx.oracles = pricedTokens;
        ctx.answers = new uint256[](ctx.oracles.length);
        for (uint256 i; i < ctx.oracles.length; ++i) {
            ctx.answers[i] = _answer(ctx.oracles[i].feed, ctx.oracles[i].maxAge);
        }
    }

    function _currentScore(Context memory ctx) private view returns (uint256 s) {
        if (!ctx.voted) return 0;
        uint256 n = IVoter(voter).poolVoteLength(address(this));
        for (uint256 i; i < n; ++i) {
            Pool memory p = _pool(ctx, IVoter(voter).poolVote(address(this), i));
            s += _share(p.value, p.others, p.own);
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
        IVoter v = IVoter(voter);
        address gauge = v.gauges(pool);
        p.alive = v.isAlive(gauge);
        if (ctx.voted) p.own = v.votes(address(this), pool);
        if (p.alive || p.own != 0) {
            address bribe = v.external_bribes(gauge);
            p.value = _bribeValue(ctx, bribe) + _bribeValue(ctx, v.internal_bribes(gauge));
            p.others = (p.alive ? v.weights(pool) : IBribe(bribe).totalSupplyAt(ctx.epoch)) - p.own;
        }
    }

    function _bribeValue(Context memory ctx, address bribe) private view returns (uint256 usd) {
        for (uint256 i; i < ctx.oracles.length; ++i) {
            if (ctx.answers[i] == 0) continue;
            Oracle memory o = ctx.oracles[i];
            (, uint256 amount,) = IBribe(bribe).rewardData(o.token, ctx.epoch);
            usd += amount * ctx.answers[i] * o.mul / o.div;
        }
    }

    function _share(uint256 b, uint256 others, uint256 x) private pure returns (uint256) {
        uint256 d = others + x;
        // forge-lint: disable-next-line(divide-before-multiply)
        return b / d * x + b % d * x / d;
    }

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

    function _transfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
        if (!ok || (ret.length == 0 ? token.code.length == 0 : !abi.decode(ret, (bool)))) {
            revert TokenCallFailed(token);
        }
    }
}
