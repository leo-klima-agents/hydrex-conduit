# hydrex-conduit

`ImmutableVeTokenConduit` is a Hydrex conduit on Base that nobody controls. veNFT holders delegate their votes to it,
and anyone can tell it how to vote, but it only accepts a new vote if it expects that vote to earn the delegators at
least $1 more in bribes. Anyone can also claim a delegator's rewards through it: the conduit pays them to the veNFT's
owner and sends a 1% fee to a fixed treasury.

The contract has no owner, no settings and no upgrade path. All of it is in
[`src/ImmutableVeTokenConduit.sol`](src/ImmutableVeTokenConduit.sol).

## How it works

### Voting

`vote(pools, weights)` takes the same arguments as the Hydrex Voter's `vote`. The conduit scores the proposal and the
vote in force, and passes the proposal on to the Voter only if its score is at least $1 higher (`MIN_GAIN`).
Otherwise it reverts with `NotBetter(oldScore, newScore)`.

A vote's score is the bribe income the delegators can expect this epoch, in USD with 18 decimals:

    score = Σ B × x / (V + x)

summed over the vote's pools, where:

- **B** is the value of the pool's external and internal bribes this epoch, counting only the whitelisted tokens
  below at their Chainlink prices;
- **V** is the other voters' votes on the pool;
- **x** is the conduit's votes on the pool, split from its voting power at the start of the epoch the same way the
  Voter splits it.

A proposal needs 1 to 20 pools, each listed once, with a non-zero weight, a live gauge, and at least one vote after
rounding. Votes don't carry over between epochs, so the first proposal of an epoch only has to be worth $1. If Hydrex
kills a gauge after the conduit voted for it, the conduit still earns that pool's bribes for the epoch, so the vote
in force keeps counting them.

Votes revert while Chainlink's sequencer uptime feed reports Base's sequencer down, and for an hour after it comes
back.

### Whitelisted tokens

| Token | Chainlink feed | Maximum age |
|---|---|---|
| WETH | ETH / USD `0x50015f8b17fb2C290Dde41fDc246ed0dcEE93a8b` | 1,500 s |
| cbBTC | cbBTC / USD `0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D` | 1,500 s |
| USDC | USDC / USD `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` | 108,000 s |
| EURC | EURC / USD `0xDAe398520e2B67cd3f27aeF9Cf14D93D927f8250` | 108,000 s |

A token counts as zero while its price is older than the maximum age, not positive, or unavailable.

### Claiming

`claim(tokenId, feeAddresses, bribeAddresses, tokens)` claims `tokens` for an opted-in veNFT from the given fee and
bribe contracts. For each token, the conduit sends 1% of what it received, rounded down, to the treasury and the rest
to the veNFT's owner, and returns the amounts claimed. Anyone can call it, for any token, and the fee is the same
whoever calls. At least one fee or bribe contract is required.

## For veNFT holders

To opt in, call `setConduitApproval(conduit, tokenId, true)` on the Hydrex VotingEscrow. This delegates your veNFT's
votes to the conduit from the next epoch and lets the conduit claim your rewards. Call it with `false` to opt out.
Transferring the veNFT clears the claim approval, so a new owner has to opt in again.

While you're opted in, anyone can claim your rewards through the conduit at any time, and you pay 1% of each claim.
You can still claim directly from the Voter without the fee, as long as nobody has claimed those rewards through the
conduit first.

## For operators

### Proposing a vote

1. For each candidate pool, read B with `poolValue(pool)` and V with the Voter's `weights(pool)`, minus
   `votes(conduit, pool)` if the conduit has already voted this epoch (`lastVoted(conduit)` is at or after the start
   of the epoch).
2. Choose up to 20 pools and weights that maximise the score. At the optimum, pool `i` gets about
   `sqrt(B_i × V_i / λ) − V_i` votes, with `λ` chosen so the votes add up to the conduit's voting power.
3. Check the result with `score(pools, weights)` and `currentScore()`, or simulate `vote` with `eth_call`, then send
   it.

`score`, `currentScore` and `poolValue` use exactly the numbers `vote` uses. Like `vote`, they revert with
`EpochStale` until someone calls `update_period()` on the Hydrex minter at the start of an epoch, and with
`NoVotingPower` if the conduit had no delegated votes when the epoch started. The Voter accepts one vote per block,
and a vote costs up to about 9.7M gas.

### Claiming rewards

For an opted-in veNFT, find the fee and bribe contracts where `earned(tokenId, token)` is positive. Claim one token
at a time and pass only the contracts that earned it: the conduit asks every contract for every token, and asking a
contract that has nothing to pay can cost as much as one that does. Bribe contracts only look back 50 epochs from a
veNFT's last claim, so after a long gap you may need to claim more than once.

Leave out any token that can't currently be sent to the treasury or the owner, such as USDC to a blocklisted
address: it makes the whole claim revert.

## Trust and limitations

- Nobody can change the conduit. A new treasury, fee or price feed means a new deployment, and holders opting in
  again.
- Hydrex's Voter, VotingEscrow and bribes are upgradeable, so the conduit is only as safe as they are.
- The bribes' owner, `0x1aE3753d9b60743A89159CcFF8E251C60B560311`, can deposit a bribe, win the vote with it and take
  the bribe back, or take any bribe's tokens. Nobody else can.
- Chainlink prices only affect votes. If a feed goes stale, its token counts as zero in both the vote in force and
  the proposal, so a worse proposal can win while it lasts; for WETH and cbBTC, that takes 25 minutes without an
  update. If the sequencer feed stops answering, votes stop, but claims still work.
- Scores use other voters' current votes. If they change theirs later, the vote in force may no longer be the best,
  and anyone can propose a better one. A vote accepted in an epoch's last block can't be replaced.
- A token that charges a fee on transfers is charged twice on its way through the conduit.
- Tokens sent to the conduit by mistake are stuck there.

## Deployment

Not deployed yet.

| | |
|---|---|
| Network | Base |
| Address | `0xa5c4128AF10A40AE2DE655AFC01556FcE181528E` |
| Voter | `0xc69E3eF39E3fFBcE2A1c570f8d3ADF76909ef17b` |
| VotingEscrow | `0x25B2ED7149fb8A05f6eF9407d9c8F878f59cd1e1` |
| Sequencer uptime feed | `0xBCF85224fc0756B9Fa45aA7892530B47e10b6433` |
| Priced tokens | the whitelist above |
| Treasury | `0x450c72de8c0079B49AcedF294a13011bd09D125B`, a 2-of-3 Safe, fixed in the source |
| Fee | 1% (`FEE_BPS = 100`), fixed in the source |
| Method | CREATE2 through `0x4e59b44847b379578588920cA78FbF26c0B4956C`, salt `keccak256("metadex.cafe/ImmutableVeTokenConduit/v1")` |

The constructor arguments are constants in [`script/Deploy.s.sol`](script/Deploy.s.sol). To deploy and verify:

```
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast --ledger
ARGS=$(jq -j .deployment.constructorArgs verification/bytecode-hashes.json)
forge verify-contract <address> src/ImmutableVeTokenConduit.sol:ImmutableVeTokenConduit --chain base \
  --constructor-args $ARGS --license-type MIT --watch
forge verify-contract <address> src/ImmutableVeTokenConduit.sol:ImmutableVeTokenConduit --chain base \
  --verifier sourcify
```

Keep `broadcast/Deploy.s.sol/8453/run-latest.json` after deploying.

## Development

You need [Foundry](https://getfoundry.sh). The fork tests and some scripts also need a Base archive RPC in
`BASE_RPC_URL`.

- `forge test` runs the unit tests, and the fork tests too when `BASE_RPC_URL` is set. The fork tests run against
  Base at the block recorded in [`test/fixtures/fork.json`](test/fixtures/fork.json).
- `test/fixtures/generate.py [block]` rewrites that fixture.
- `script/check-signatures.sh` checks the interfaces in `src/interfaces/` against the Hydrex sources vendored in
  `test/upstream/`.
- `script/check-verification.sh` checks that `verification/` matches the build.
- `script/refresh-verification.sh` regenerates `verification/` after a change to the source or the deploy script.

[`test/upstream/UPSTREAM.md`](test/upstream/UPSTREAM.md) records the Hydrex contracts and Chainlink feeds the conduit
is written against, and the Hydrex behaviour it relies on.

The contract compiles with solc 0.8.37 for `prague`, via-IR, with 1,000,000 optimizer runs. Builds are reproducible.

## License

MIT. `REUSE.toml` records the copyright and license of every file.
