#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

ARTIFACT=out/ImmutableVeTokenConduit.sol/ImmutableVeTokenConduit.json
HASHES=verification/bytecode-hashes.json
INPUT=verification/ImmutableVeTokenConduit.standard-input.json
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
expect .creationCodeKeccak "$(cast keccak "$creation")"
expect .solc "$(jq -j '.metadata.compiler.version' "$ARTIFACT")"
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
