#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

U=test/upstream
I=src/interfaces
status=0
checked=()

sig() {
  awk -v name="$2" '
    { src = src " " $0 }
    function types(list,   n, parts, i, out, t) {
      n = split(list, parts, ",")
      out = ""
      for (i = 1; i <= n; i++) {
        t = parts[i]
        gsub(/^[ \t]+/, "", t)
        sub(/[ \t].*$/, "", t)
        sub(/^IVotingEscrowV2_Data\.ApprovalActionType/, "uint8", t)
        if (t != "") out = out (out == "" ? "" : ",") t
      }
      return out
    }
    END {
      i = index(src, "function " name "(")
      if (i == 0) exit 1
      s = substr(src, i + length("function " name "("))
      args = substr(s, 1, index(s, ")") - 1)
      rest = substr(s, index(s, ")") + 1)
      rest = substr(rest, 1, match(rest, /[;{]/) - 1)
      ret = ""
      j = index(rest, "returns")
      if (j) {
        r = substr(rest, j)
        r = substr(r, index(r, "(") + 1)
        ret = substr(r, 1, index(r, ")") - 1)
      }
      printf "%s(%s)(%s)\n", name, types(args), types(ret)
    }' "$1"
}

reward_data_sig() {
  local file=$U/hydrex/bribe/BribeV2.sol
  grep -qF 'mapping(address => mapping(uint256 => Reward)) public rewardData;' "$file" || return 1
  tr -s '[:space:]' ' ' < "$file" |
    grep -F 'struct Reward { uint256 periodFinish; uint256 rewardsPerEpoch; uint256 lastUpdateTime; }' > /dev/null || return 1
  grep -qF "returns (uint256 periodFinish, uint256 rewardsPerEpoch, uint256 lastUpdateTime);" "$I/IBribe.sol" || return 1
  echo "rewardData(address,uint256)(uint256,uint256,uint256)"
}

reward_tokens_sig() {
  grep -qF 'address[] public rewardTokens;' "$U/hydrex/bribe/BribeV2.sol" || return 1
  grep -qF "function rewardTokens(uint256 index) external view returns (address);" "$I/IBribe.sol" || return 1
  echo "rewardTokens(uint256)(address)"
}

check() {
  local iface=$1 name=$2 upstream=$3 ours theirs
  checked+=("$name")
  ours=$(sig "$I/$iface" "$name") || { echo "::error::$name not declared in $I/$iface" >&2; status=1; return; }
  if [ "$upstream" = mapping ]; then
    theirs=$(reward_data_sig) || theirs=missing
  elif [ "$upstream" = array ]; then
    theirs=$(reward_tokens_sig) || theirs=missing
  else
    theirs=$(sig "$U/$upstream" "$name") || theirs=missing
  fi
  if [ "$ours" != "$theirs" ]; then
    echo "::error::$name: $I/$iface has $ours, $upstream has $theirs" >&2
    status=1
  else
    echo "$ours ok ($upstream)"
  fi
}

check IVoter.sol vote hydrex/voter/IVoterV5_Logic.sol
check IVoter.sol _epochTimestamp hydrex/voter/IVoterV5_Logic.sol
check IVoter.sol weights hydrex/voter/IVoterV5_Logic.sol
check IVoter.sol poolVoteLength hydrex/voter/IVoterV5_Logic.sol
check IVoter.sol gauges hydrex/voter/IVoterV5_Storage.sol
check IVoter.sol isAlive hydrex/voter/IVoterV5_Storage.sol
check IVoter.sol external_bribes hydrex/voter/IVoterV5_Storage.sol
check IVoter.sol internal_bribes hydrex/voter/IVoterV5_Storage.sol
check IVoter.sol votes hydrex/voter/IVoterV5_Storage.sol
check IVoter.sol poolVote hydrex/voter/IVoterV5_Storage.sol
check IVoter.sol lastVoted hydrex/voter/IVoterV5_Storage.sol
check IVoter.sol claimBribesToRecipientByTokenId hydrex/voter/IVoterV5_ClaimLogic.sol
check IVoter.sol claimFeesToRecipientByTokenId hydrex/voter/IVoterV5_ClaimLogic.sol
check IVotingEscrow.sol getPastVotes hydrex/votingescrow/IVotes.sol
check IVotingEscrow.sol setConduitApprovalConfig hydrex/votingescrow/IVotingEscrowV2_Logic.sol
check IBribe.sol rewardData mapping
check IBribe.sol totalSupplyAt hydrex/bribe/BribeV2.sol
check IBribe.sol rewardTokens array
check IAlgebraFactory.sol poolByPair algebra/core/IAlgebraFactory.sol
check IAlgebraPool.sol plugin algebra/core/IAlgebraPoolState.sol
check IVolatilityOracle.sol getTimepoints algebra/plugin/IVolatilityOracle.sol
check IVolatilityOracle.sol getTimepoints algebra/upgradeable-plugin/IVolatilityOracle.sol

declared=$(grep -ohE 'function [A-Za-z_]+\(' "$I/IVoter.sol" "$I/IVotingEscrow.sol" "$I/IBribe.sol" \
  "$I/IAlgebraFactory.sol" "$I/IAlgebraPool.sol" "$I/IVolatilityOracle.sol" | sed -E 's/function |\(//g' | sort)
unchecked=$(comm -23 <(echo "$declared") <(printf '%s\n' "${checked[@]}" | sort -u) | grep -vx ownerOf || true)
if [ -n "$unchecked" ]; then
  echo "::error::not checked against upstream: $unchecked" >&2
  status=1
fi

exit $status
