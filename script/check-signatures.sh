#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Léo de Souza
# SPDX-License-Identifier: MIT
# Checks that every Hydrex member declared in src/interfaces/ has the same argument and return types as its
# declaration in the vendored sources under test/upstream/hydrex/.
set -euo pipefail
cd "$(dirname "$0")/.."

U=test/upstream/hydrex
I=src/interfaces
status=0

# Prints name(argument types)(return types) for the first declaration of function $2 in file $1.
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

# BribeV2 declares rewardData as a public mapping of a struct, so its getter returns the struct's fields in order.
# The conduit reads the second one, so the field names must match too.
reward_data_sig() {
  local file=$U/bribe/BribeV2.sol types names
  grep -qF 'mapping(address => mapping(uint256 => Reward)) public rewardData;' "$file" || return 1
  types=$(awk '/struct Reward \{/ { on = 1; next } on && /\}/ { exit } on { printf "%s%s", sep, $1; sep = "," }' "$file")
  names=$(awk '/struct Reward \{/ { on = 1; next } on && /\}/ { exit } on { sub(/;.*/, "", $2); printf "%s%s", sep, $2; sep = "," }' "$file")
  [ "$names" = "periodFinish,rewardsPerEpoch,lastUpdateTime" ] || return 1
  grep -qF "returns (uint256 periodFinish, uint256 rewardsPerEpoch, uint256 lastUpdateTime);" "$I/IBribe.sol" || return 1
  echo "rewardData(address,uint256)($types)"
}

check() {
  local iface=$1 name=$2 upstream=$3 ours theirs
  ours=$(sig "$I/$iface" "$name") || { echo "::error::$name not declared in $I/$iface" >&2; status=1; return; }
  if [ "$upstream" = mapping ]; then
    theirs=$(reward_data_sig) || theirs=missing
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

check IVoter.sol vote voter/IVoterV5_Logic.sol
check IVoter.sol _epochTimestamp voter/IVoterV5_Logic.sol
check IVoter.sol weights voter/IVoterV5_Logic.sol
check IVoter.sol poolVoteLength voter/IVoterV5_Logic.sol
check IVoter.sol gauges voter/IVoterV5_Storage.sol
check IVoter.sol isAlive voter/IVoterV5_Storage.sol
check IVoter.sol external_bribes voter/IVoterV5_Storage.sol
check IVoter.sol internal_bribes voter/IVoterV5_Storage.sol
check IVoter.sol votes voter/IVoterV5_Storage.sol
check IVoter.sol poolVote voter/IVoterV5_Storage.sol
check IVoter.sol lastVoted voter/IVoterV5_Storage.sol
check IVoter.sol claimBribesToRecipientByTokenId voter/IVoterV5_ClaimLogic.sol
check IVoter.sol claimFeesToRecipientByTokenId voter/IVoterV5_ClaimLogic.sol
check IVotingEscrow.sol getPastVotes votingescrow/IVotes.sol
check IVotingEscrow.sol setConduitApprovalConfig votingescrow/IVotingEscrowV2_Logic.sol
check IBribe.sol rewardData mapping

declared=$(grep -ohE 'function [A-Za-z_]+\(' "$I/IVoter.sol" "$I/IVotingEscrow.sol" "$I/IBribe.sol" | sed -E 's/function |\(//g' | sort)
checked=$(grep -oE '^check I[A-Za-z]+\.sol [A-Za-z_]+' script/check-signatures.sh | awk '{ print $3 }' | sort)
unchecked=$(comm -23 <(echo "$declared") <(echo "$checked") | grep -vx ownerOf || true)
if [ -n "$unchecked" ]; then
  echo "::error::not checked against upstream: $unchecked" >&2
  status=1
fi

exit $status
