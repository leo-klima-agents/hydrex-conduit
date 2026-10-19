#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Léo de Souza
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/.."

ARTIFACT=out/ImmutableVeTokenConduit.sol/ImmutableVeTokenConduit.json
HASHES=verification/bytecode-hashes.json
INPUT=verification/ImmutableVeTokenConduit.standard-input.json
SRC=src/ImmutableVeTokenConduit.sol
SCRIPT=script/Deploy.s.sol
UPSTREAM=test/upstream/UPSTREAM.md
[ -f "$ARTIFACT" ] || { echo "::error::$ARTIFACT missing; run forge build" >&2; exit 1; }
[ -f "$HASHES" ] || { echo "::error::$HASHES missing; run script/refresh-verification.sh" >&2; exit 1; }
[ -f "$INPUT" ] || { echo "::error::$INPUT missing; run script/refresh-verification.sh" >&2; exit 1; }
status=0

expect() {
  local recorded
  recorded=$(jq -r "$1 // \"\"" "$HASHES")
  if [ "$recorded" != "$2" ]; then
    echo "::error::$1: recorded '$recorded', built '$2'" >&2
    status=1
  else
    echo "$1 ok"
  fi
}

creation=$(jq -r '.bytecode.object' "$ARTIFACT")
expect .runtimeTemplateKeccak "$(cast keccak "$(jq -r '.deployedBytecode.object' "$ARTIFACT")")"
expect .creationCodeKeccak "$(cast keccak "$creation")"
expect .solc "$(jq -r '.metadata.compiler.version' "$ARTIFACT")"

source_constant() { grep -oE "constant $1 = [0-9a-fA-Fx_]+;" "$SRC" | sed -E 's/.* = ([0-9a-fA-Fx_]+);/\1/' | tr -d _; }
treasury=$(cast to-check-sum-address "$(source_constant TREASURY)")
expect .treasury "$treasury"
expect .feeBps "$(source_constant FEE_BPS)"
for row in "| \`TREASURY\` | \`$treasury\` |" "| \`FEE_BPS\` | \`$(source_constant FEE_BPS)\` |"; do
  if grep -qF "$row" "$UPSTREAM"; then echo "$UPSTREAM $row ok"; else echo "::error::$UPSTREAM lacks $row" >&2; status=1; fi
done

script_constant() { grep -oE "constant $1 = [0-9a-fA-Fx_]+;" "$SCRIPT" | sed -E 's/.* = ([0-9a-fA-Fx_]+);/\1/' | tr -d _; }
addr() { cast to-check-sum-address "$(script_constant "$1")"; }
expect .deployment.voter "$(addr VOTER)"
expect .deployment.veToken "$(addr VE_TOKEN)"
expect .deployment.usdc "$(addr USDC)"
expect .deployment.sequencerFeed "$(addr SEQUENCER_FEED)"
expect '.deployment.routers | join(",")' "$(addr KYBER_ROUTER),$(addr ONEINCH_ROUTER)"
expect '.deployment.pricedTokens | join(",")' "$(addr WETH),$(addr CBBTC),$(addr USDC),$(addr EURC)"
expect '.deployment.feeds | join(",")' "$(addr ETH_USD),$(addr CBBTC_USD),$(addr USDC_USD),$(addr EURC_USD)"
fast=$(script_constant FAST_MAX_AGE)
slow=$(script_constant SLOW_MAX_AGE)
expect '.deployment.maxAges | map(tostring) | join(",")' "$fast,$fast,$slow,$slow"
expect .saltPreimage "$(grep -oE 'SALT_PREIMAGE = "[^"]+"' "$SCRIPT" | cut -d'"' -f2)"
expect .salt "$(cast keccak "$(jq -r .saltPreimage "$HASHES")")"

priced=$(jq -r '.deployment | [.pricedTokens, .feeds, .maxAges] | transpose | map("(" + (map(tostring) | join(",")) + ")") | join(",")' "$HASHES")
args=$(cast abi-encode 'constructor(address,address,address,address,address[],(address,address,uint256)[])' \
  "$(jq -r .deployment.voter "$HASHES")" "$(jq -r .deployment.veToken "$HASHES")" \
  "$(jq -r .deployment.usdc "$HASHES")" "$(jq -r .deployment.sequencerFeed "$HASHES")" \
  "[$(jq -r '.deployment.routers | join(",")' "$HASHES")]" "[$priced]")
expect .deployment.constructorArgs "$args"
expect .deployment.address "$(cast create2 --deployer "$(jq -r .create2Deployer "$HASHES")" --salt "$(jq -r .salt "$HASHES")" --init-code "${creation}${args#0x}" | grep -oE '0x[0-9a-fA-F]{40}' | head -n1)"

projection='del(.settings.outputSelection)'
current=$(forge verify-contract --show-standard-json-input 0x0000000000000000000000000000000000000001 src/ImmutableVeTokenConduit.sol:ImmutableVeTokenConduit | jq -S "$projection")
if [ "$current" != "$(jq -S "$projection" "$INPUT")" ]; then
  echo "::error::$INPUT is stale" >&2
  status=1
else
  echo "$INPUT ok"
fi

exit $status
