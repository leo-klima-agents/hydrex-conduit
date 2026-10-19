#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${BASE_RPC_URL:?set BASE_RPC_URL: the constructor reads the live feeds}"
forge build
forge script script/Hashes.s.sol --sig 'record()' --fork-url "$BASE_RPC_URL"
forge verify-contract --show-standard-json-input 0x0000000000000000000000000000000000000001 \
  src/ImmutableVeTokenConduit.sol:ImmutableVeTokenConduit > verification/ImmutableVeTokenConduit.standard-input.json
./script/check-verification.sh
