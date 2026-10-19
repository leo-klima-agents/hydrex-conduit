// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IMinter.sol";
import "../interfaces/IVoter.sol";
import "./VotingEscrow/IVotingEscrowV2.sol";
import "../interfaces/IVersionable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Constants.sol";
import "./IBribe.sol";

/**
 * @title BribeV2
 * @dev
 *  - If a user delegates their voting power and the delegatee does not vote, the owner will not receive rewards.
 *  - WARN Premature burn of VotingEscrow token will result in loss of rewards.
 *  - WARN if VotingEscrow is listed for sale on a marketplace, there is a risk of rewards being
 *      front-run before purchase.
 *  - WARN The owner (teamMultisig) can withdraw tokens from the bribe contract using recoverERC20AndUpdateData
 *      or emergencyRecoverERC20, which could empty out tokens from the contract.
 */
contract BribeV2 is IBribe_Init, IVersionable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    string public constant override VERSION = "2.1.0";
    /// @dev For upgradeable contracts, this needs to be initialized in the initialize function. Leaving as is for storage layout compatibility.
    uint256 public WEEK = Constants.EPOCH; // rewards are released over 7 days
    uint256 public firstBribeTimestamp;

    /* ========== STATE VARIABLES ========== */

    struct Reward {
        uint256 periodFinish;
        uint256 rewardsPerEpoch;
        uint256 lastUpdateTime;
    }

    mapping(address => mapping(uint256 => Reward)) public rewardData; // token -> startTimestamp -> Reward
    mapping(address => bool) public isRewardToken;
    address[] public rewardTokens;
    address public voter;
    address public bribeFactory;
    address public minter;
    address public ve;
    address public owner;

    string public TYPE;

    // owner -> reward token -> lastTime
    mapping(uint256 => mapping(address => uint256)) public tokenTimestamp;

    //uint256 private _totalSupply;
    mapping(uint256 => uint256) private _totalSupply;
    mapping(address => mapping(uint256 => uint256)) private _balances; //owner -> timestamp -> amount

    /* ========== CONSTRUCTOR ========== */

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _voter,
        address _bribeFactory,
        string memory _type
    ) external override initializer {
        require(_bribeFactory != address(0) && _voter != address(0) && _owner != address(0));
        voter = _voter;
        bribeFactory = _bribeFactory;
        firstBribeTimestamp = 0;
        ve = IVoter(_voter).ve();
        minter = IVoter(_voter).minter();
        require(minter != address(0));
        owner = _owner;
        TYPE = _type;
        WEEK = Constants.EPOCH;
    }

    /// @notice get the current epoch
    function getEpochStart() public view returns (uint256) {
        return IMinter(minter).active_period();
    }

    /// @notice get next epoch (where bribes are saved)
    function getNextEpochStart() public view returns (uint256) {
        return getEpochStart() + WEEK;
    }

    /* ========== VIEWS ========== */

    /// @notice get the length of the reward tokens
    function rewardsListLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    /// @notice get the last totalSupply (total votes for a pool)
    function totalSupply() external view returns (uint256) {
        uint256 _currentEpochStart = IMinter(minter).active_period(); // claim until current epoch
        return _totalSupply[_currentEpochStart];
    }

    /// @notice get a totalSupply given a timestamp
    function totalSupplyAt(uint256 _timestamp) external view returns (uint256) {
        return _totalSupply[_timestamp];
    }

    /// @notice read the balanceOf the tokenId at a given timestamp
    function balanceOfAt(uint256 tokenId, uint256 _timestamp) public view returns (uint256) {
        address _owner = IVotingEscrowV2(ve).ownerOf(tokenId);
        return _balances[_owner][_timestamp];
    }

    /// @notice get last deposit available given a tokenID
    function balanceOf(uint256 tokenId) public view returns (uint256) {
        uint256 _timestamp = getEpochStart();
        address _owner = IVotingEscrowV2(ve).ownerOf(tokenId);
        return _balances[_owner][_timestamp];
    }

    /// @notice get the balance of an owner in the current epoch
    function balanceOfOwner(address _owner) public view returns (uint256) {
        uint256 _timestamp = getEpochStart();
        return _balances[_owner][_timestamp];
    }

    /// @notice get the balance of an owner given a timestamp
    function balanceOfOwnerAt(address _owner, uint256 _timestamp) public view returns (uint256) {
        return _balances[_owner][_timestamp];
    }

    /// @notice Read earned amount given a tokenID and _rewardToken
    function earned(uint256 tokenId, address _rewardToken) public view returns (uint256) {
        uint256 k = 0;
        uint256 reward = 0;
        uint256 _endTimestamp = IMinter(minter).active_period(); // claim until current epoch
        uint256 _tokenLastTime = tokenTimestamp[tokenId][_rewardToken];

        if (_endTimestamp == _tokenLastTime) {
            return 0;
        }

        // if user first time then set it to first bribe - week to avoid any timestamp problem
        if (_tokenLastTime < firstBribeTimestamp) {
            (, uint48 ts) = IVotingEscrowV2(ve).getFirstEscrowPoint(tokenId);
            uint256 start = (ts / WEEK) * WEEK;
            _tokenLastTime = start > firstBribeTimestamp ? start : firstBribeTimestamp - WEEK;
        }

        for (k; k < 50; k++) {
            if (_tokenLastTime >= _endTimestamp) {
                // if we pass the current epoch, exit
                break;
            }
            reward += _earnedTokenId(tokenId, _rewardToken, uint48(_tokenLastTime));
            _tokenLastTime += WEEK;
        }
        return reward;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IBribe).interfaceId || interfaceId == type(IVersionable).interfaceId;
    }

    /// @notice Read earned amount given address and reward token, returns the rewards and the last user timestamp (used in case user do not claim since 50+epochs)
    function _earnedWithTimestampTokenId(
        uint256 _tokenId,
        address _rewardToken
    ) private view returns (uint256, uint256) {
        uint256 k = 0;
        uint256 reward = 0;
        uint256 _endTimestamp = IMinter(minter).active_period(); // claim until current epoch
        uint256 _tokenLastTime = tokenTimestamp[_tokenId][_rewardToken];

        // if user first time then set it to first bribe - week to avoid any timestamp problem
        if (_tokenLastTime < firstBribeTimestamp) {
            (, uint48 ts) = IVotingEscrowV2(ve).getFirstEscrowPoint(_tokenId);
            uint256 start = (ts / WEEK) * WEEK;
            _tokenLastTime = start > firstBribeTimestamp ? start : firstBribeTimestamp - WEEK;
        }

        for (k; k < 50; k++) {
            if (_tokenLastTime >= _endTimestamp) {
                // if we pass the current epoch, exit
                break;
            }
            reward += _earnedTokenId(_tokenId, _rewardToken, uint48(_tokenLastTime));
            _tokenLastTime += WEEK;
        }
        return (reward, _tokenLastTime);
    }

    /// @notice get the earned rewards
    function earnedOwner(address _owner, address _rewardToken, uint256 _timestamp) public view returns (uint256) {
        uint256 _balance = balanceOfOwnerAt(_owner, _timestamp);
        if (_balance == 0) {
            return 0;
        } else {
            uint256 _rewardPerToken = rewardPerToken(_rewardToken, _timestamp);
            uint256 _rewards = (_rewardPerToken * _balance) / 1e32;
            return _rewards;
        }
    }

    /// @notice get the earned rewards rounded to closest previous active period
    function earnedTokenId(uint256 _tokenId, address _rewardToken, uint48 _timestamp) external view returns (uint256) {
        uint48 onClockTimestamp = uint48((_timestamp / WEEK) * WEEK);
        return _earnedTokenId(_tokenId, _rewardToken, onClockTimestamp);
    }

    /// @notice get the earned rewards
    function _earnedTokenId(
        uint256 _tokenId,
        address _rewardToken,
        uint48 _weightTimestamp
    ) internal view returns (uint256) {
        address _delegatee = IVotingEscrowV2(ve).delegates(_tokenId, _weightTimestamp);
        if (_delegatee == address(0)) return 0;
        uint256 _power = IVotingEscrowV2(ve).balanceOfNFTAt(_tokenId, _weightTimestamp);
        if (_power == 0) return 0;

        uint256 _balance = balanceOfOwnerAt(_delegatee, _weightTimestamp);
        if (_balance == 0) return 0;

        uint256 _delegateePower = IVotingEscrowV2(ve).getPastVotes(_delegatee, _weightTimestamp);
        if (_delegateePower == 0) return 0;

        uint256 _weight = (_power * 1e18) / _delegateePower;

        if (_balance == 0 || _weight == 0) {
            return 0;
        } else {
            uint256 _rewardPerToken = rewardPerToken(_rewardToken, _weightTimestamp);
            uint256 _rewards = (((_rewardPerToken * _balance) / 1e32) * _weight) / 1e18;
            return _rewards;
        }
    }

    /// @notice get the rewards for token
    function rewardPerToken(address _rewardsToken, uint256 _timestamp) public view returns (uint256) {
        if (_totalSupply[_timestamp] == 0) {
            return rewardData[_rewardsToken][_timestamp].rewardsPerEpoch * 1e32;
        }
        return (rewardData[_rewardsToken][_timestamp].rewardsPerEpoch * 1e32) / _totalSupply[_timestamp];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice User votes deposit
    /// @dev    called on voter.vote() or voter.poke()
    ///         we save into owner "address" and not "tokenID".
    ///         Owner must reset before transferring token
    function deposit(uint256 amount, address user) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        require(msg.sender == voter);
        uint256 _startTimestamp = IMinter(minter).active_period();
        uint256 _oldSupply = _totalSupply[_startTimestamp];
        uint256 _lastBalance = _balances[user][_startTimestamp];

        _totalSupply[_startTimestamp] = _oldSupply + amount;
        _balances[user][_startTimestamp] = _lastBalance + amount;

        emit Staked(user, amount);
    }

    /// @notice User votes withdrawal
    /// @dev    called on voter.reset()
    function withdraw(uint256 amount, address user) external nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(msg.sender == voter);
        uint256 _startTimestamp = IMinter(minter).active_period();

        // incase of bribe contract reset in gauge proxy
        if (amount <= _balances[user][_startTimestamp]) {
            uint256 _oldSupply = _totalSupply[_startTimestamp];
            uint256 _oldBalance = _balances[user][_startTimestamp];
            _totalSupply[_startTimestamp] = _oldSupply - amount;
            _balances[user][_startTimestamp] = _oldBalance - amount;
            emit Withdrawn(user, amount);
        }
    }

    /// @notice Claim the TOKENID rewards
    function _getReward(uint256 tokenId, address _recipient, address[] memory tokens) internal {
        uint256 _tokenLastTime;
        uint256 reward = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            address _rewardToken = tokens[i];
            (reward, _tokenLastTime) = _earnedWithTimestampTokenId(tokenId, _rewardToken);
            if (reward > 0) {
                IERC20(_rewardToken).safeTransfer(_recipient, reward);
                emit RewardPaid(_recipient, _rewardToken, reward);
            }
            tokenTimestamp[tokenId][_rewardToken] = _tokenLastTime;
        }
    }

    // @notice Claim the TOKENID rewards
    function getReward(uint256 tokenId, address[] memory tokens) external nonReentrant {
        require(IVotingEscrowV2(ve).isApprovedOrOwner(msg.sender, tokenId));
        address _owner = IVotingEscrowV2(ve).ownerOf(tokenId);
        return _getReward(tokenId, _owner, tokens);
    }

    /// @notice Claim the rewards given msg.sender
    function getReward(address[] memory tokens) external nonReentrant {
        address _owner = msg.sender;
        uint256 balance = IVotingEscrowV2(ve).balanceOf(_owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = IVotingEscrowV2(ve).tokenOfOwnerByIndex(_owner, i);
            _getReward(tokenId, _owner, tokens);
        }
    }

    /// @notice Claim rewards from voter
    function getRewardForOwner(uint256 tokenId, address[] memory tokens) public nonReentrant {
        require(msg.sender == voter);
        address _owner = IVotingEscrowV2(ve).ownerOf(tokenId);
        return _getReward(tokenId, _owner, tokens);
    }

    /// @notice Claim rewards from voter
    function getRewardForAddress(address _owner, address[] memory tokens) public nonReentrant {
        require(msg.sender == voter);
        uint256 balance = IVotingEscrowV2(ve).balanceOf(_owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = IVotingEscrowV2(ve).tokenOfOwnerByIndex(_owner, i);
            _getReward(tokenId, _owner, tokens);
        }
    }

    function getRewardToRecipient(uint256 tokenId, address[] memory tokens, address _recipient) external nonReentrant {
        require(IVotingEscrowV2(ve).isApprovedClaimRedirectOrOwner(msg.sender, tokenId) || msg.sender == voter, "Not authorized");
        return _getReward(tokenId, _recipient, tokens);
    }

    /// @notice Claim rewards from voter
    function getRewardForAddressToRecipient(
        address _owner,
        address[] memory tokens,
        address _recipient
    ) public nonReentrant {
        require(IVotingEscrowV2(ve).isClaimRedirectApprovedForAll(_owner, msg.sender) || msg.sender == voter, "Not authorized");
        uint256 balance = IVotingEscrowV2(ve).balanceOf(_owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = IVotingEscrowV2(ve).tokenOfOwnerByIndex(_owner, i);
            _getReward(tokenId, _recipient, tokens);
        }
    }

    /// @notice Notify a bribe amount
    /// @dev    Rewards are saved into NEXT EPOCH mapping.
    function notifyRewardAmount(address _rewardsToken, uint256 reward) external nonReentrant {
        require(isRewardToken[_rewardsToken], "reward token not verified");
        /// @dev Account for tax on transfer tokens
        uint256 balanceBefore = IERC20(_rewardsToken).balanceOf(address(this));
        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), reward);
        uint256 balanceAfter = IERC20(_rewardsToken).balanceOf(address(this));
        uint256 effectiveTransfer = balanceAfter - balanceBefore;

        uint256 _startTimestamp = IMinter(minter).active_period(); //period points to the current thursday. Bribes are distributed from next epoch (thursday)
        if (firstBribeTimestamp == 0) {
            firstBribeTimestamp = _startTimestamp;
        }

        uint256 _lastReward = rewardData[_rewardsToken][_startTimestamp].rewardsPerEpoch;

        rewardData[_rewardsToken][_startTimestamp].rewardsPerEpoch = _lastReward + effectiveTransfer;
        rewardData[_rewardsToken][_startTimestamp].lastUpdateTime = block.timestamp;
        rewardData[_rewardsToken][_startTimestamp].periodFinish = _startTimestamp;

        emit RewardAdded(_rewardsToken, effectiveTransfer, _startTimestamp);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice add rewards tokens
    function addRewardTokens(address[] memory _rewardsToken) public onlyAllowed {
        uint256 i = 0;
        for (i; i < _rewardsToken.length; i++) {
            _addRewardToken(_rewardsToken[i]);
        }
    }

    /// @notice add a single reward token
    function addRewardToken(address _rewardsToken) public onlyAllowed {
        _addRewardToken(_rewardsToken);
    }

    function _addRewardToken(address _rewardsToken) internal {
        if (!isRewardToken[_rewardsToken]) {
            isRewardToken[_rewardsToken] = true;
            rewardTokens.push(_rewardsToken);
        }
    }

    /// @notice Recover some ERC20 from the contract and updated given bribe
    function recoverERC20AndUpdateData(address tokenAddress, uint256 tokenAmount) external onlyAllowed {
        require(tokenAmount <= IERC20(tokenAddress).balanceOf(address(this)));

        uint256 _startTimestamp = IMinter(minter).active_period();
        uint256 _lastReward = rewardData[tokenAddress][_startTimestamp].rewardsPerEpoch;
        rewardData[tokenAddress][_startTimestamp].rewardsPerEpoch = _lastReward - tokenAmount;
        rewardData[tokenAddress][_startTimestamp].lastUpdateTime = block.timestamp;

        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /// @notice Recover some ERC20 from the contract.
    /// @dev    Be careful --> if called then getReward() at last epoch will fail because some reward are missing!
    ///         Think about calling recoverERC20AndUpdateData()
    function emergencyRecoverERC20(address tokenAddress, uint256 tokenAmount) external onlyAllowed {
        require(tokenAmount <= IERC20(tokenAddress).balanceOf(address(this)));
        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /// @notice Set a new voter
    function setVoter(address _Voter) external onlyAllowed {
        require(_Voter != address(0));
        voter = _Voter;
    }

    /// @notice Set a new minter
    function setMinter(address _minter) external onlyAllowed {
        require(_minter != address(0));
        minter = _minter;
    }

    /// @notice Set a new Owner
    event SetOwner(address indexed _owner);

    function setOwner(address _owner) external onlyAllowed {
        require(_owner != address(0));
        owner = _owner;
        emit SetOwner(_owner);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyAllowed() {
        require((msg.sender == owner || msg.sender == bribeFactory), "permission is denied!");
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(address indexed rewardToken, uint256 reward, uint256 startTimestamp);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed rewardsToken, uint256 reward);
    event Recovered(address indexed token, uint256 amount);
}
