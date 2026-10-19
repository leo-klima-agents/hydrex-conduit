#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

ARTIFACT=out/ImmutableVeTokenConduit.sol/ImmutableVeTokenConduit.json
HASHES=verification/bytecode-hashes.json
INPUT=verification/ImmutableVeTokenConduit.standard-input.json
SRC=src/ImmutableVeTokenConduit.sol
SCRIPT=script/Deploy.s.sol
[ -f "$ARTIFACT" ] || { echo "::error::$ARTIFACT missing; run forge build" >&2; exit 1; }
[ -f "$HASHES" ] || { echo "::error::$HASHES missing; run script/refresh-verification.sh" >&2; exit 1; }
[ -f "$INPUT" ] || { echo "::error::$INPUT missing; run script/refresh-verification.sh" >&2; exit 1; }
status=0

expect() {
  local recorded
  recorded=$(jq -j "$1 // \"\"" "$HASHES")
  if [ "$recorded" != "$2" ]; then
    echo "::error::$1: recorded '$recorded', built '$2'" >&2
    status=1
  else
    echo "$1 ok"
  fi
}

creation=$(jq -j '.bytecode.object' "$ARTIFACT")
expect .runtimeTemplateKeccak "$(cast keccak "$(jq -j '.deployedBytecode.object' "$ARTIFACT")")"
expect .creationCodeKeccak "$(cast keccak "$creation")"
expect .solc "$(jq -j '.metadata.compiler.version' "$ARTIFACT")"

constant() { grep -oE "constant $2 = [0-9a-fA-Fx_]+;" "$1" | sed -E 's/.* = ([0-9a-fA-Fx_]+);/\1/' | tr -d _; }
expect .treasury "$(cast to-check-sum-address "$(constant "$SRC" TREASURY)")"
expect .feeBps "$(constant "$SRC" FEE_BPS)"

addr() { cast to-check-sum-address "$(constant "$SCRIPT" "$1")"; }
expect .deployment.voter "$(addr VOTER)"
expect .deployment.veToken "$(addr VE_TOKEN)"
expect .deployment.sequencerFeed "$(addr SEQUENCER_FEED)"
expect '.deployment.pricedTokens | join(",")' "$(addr WETH),$(addr CBBTC),$(addr USDC),$(addr EURC)"
expect '.deployment.feeds | join(",")' "$(addr ETH_USD),$(addr CBBTC_USD),$(addr USDC_USD),$(addr EURC_USD)"
fast=$(constant "$SCRIPT" FAST_MAX_AGE)
slow=$(constant "$SCRIPT" SLOW_MAX_AGE)
expect '.deployment.maxAges | map(tostring) | join(",")' "$fast,$fast,$slow,$slow"
expect .saltPreimage "$(grep -oE 'SALT_PREIMAGE = "[^"]+"' "$SCRIPT" | cut -d'"' -f2)"
expect .salt "$(cast keccak "$(jq -j .saltPreimage "$HASHES")")"

priced=$(jq -j '.deployment | [.pricedTokens, .feeds, .maxAges] | transpose | map("(" + (map(tostring) | join(",")) + ")") | join(",")' "$HASHES")
args=$(cast abi-encode 'constructor(address,address,address,(address,address,uint256)[])' \
  "$(jq -j .deployment.voter "$HASHES")" "$(jq -j .deployment.veToken "$HASHES")" \
  "$(jq -j .deployment.sequencerFeed "$HASHES")" "[$priced]")
expect .deployment.constructorArgs "$args"
expect .deployment.address "$(cast create2 --deployer "$(jq -j .create2Deployer "$HASHES")" --salt "$(jq -j .salt "$HASHES")" --init-code "${creation}${args#0x}" | grep -oE '0x[0-9a-fA-F]{40}' | head -n1)"

projection='del(.settings.outputSelection)'
current=$(forge verify-contract --show-standard-json-input 0x0000000000000000000000000000000000000001 src/ImmutableVeTokenConduit.sol:ImmutableVeTokenConduit | jq -S "$projection")
if [ "$current" != "$(jq -S "$projection" "$INPUT")" ]; then
  echo "::error::$INPUT is stale" >&2
  status=1
else
  echo "$INPUT ok"
fi

address=$(jq -j .deployment.address "$HASHES")
if grep -qF "\`$address\`" README.md; then
  echo "README.md address ok"
else
  echo "::error::README.md does not show $address" >&2
  status=1
fi

exit $status
