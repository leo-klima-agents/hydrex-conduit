# hydrex-conduit

`ImmutableVeTokenConduit` is a Hydrex conduit on Base that nobody controls. veNFT holders delegate their votes to it,
and anyone can tell it how to vote, but it only accepts a new vote if it expects that vote to earn the delegators at
least $1 more in bribes. Anyone can also claim a delegator's rewards through it: the conduit pays them to the veNFT's
owner and sends a 1% fee to a fixed treasury.

The contract has no owner, no settings and no upgrade path. All of it is in
[`src/ImmutableVeTokenConduit.sol`](src/ImmutableVeTokenConduit.sol), deployed on Base at
[`0x692c323B425A9DfeebE302F56168a7798D93EAC5`](https://basescan.org/address/0x692c323B425A9DfeebE302F56168a7798D93EAC5#code).
This is version 2, which also counts trading fees in tokens that have no Chainlink feed. Version 1, at
[`0x8B79159681aEbeC096D06F3d996fCd2f72e54f8B`](https://basescan.org/address/0x8B79159681aEbeC096D06F3d996fCd2f72e54f8B#code),
keeps working as it is.

## How it works

### Voting

`vote(pools, weights)` takes the same arguments as the Hydrex Voter's `vote`. The conduit scores the proposal and the
vote in force, and passes the proposal on to the Voter only if its score is at least $1 higher (`MIN_GAIN`).
Otherwise it reverts with `NotBetter(oldScore, newScore)`.

A vote's score is the bribe income the delegators can expect this epoch, in USD with 18 decimals:

    score = Σ B × x / (V + x)

summed over the vote's pools, where:

- **B** is the value of the pool's external and internal bribes this epoch: the whitelisted tokens below at their
  Chainlink prices, plus some of the pool's trading fees in other tokens (see [Fees in other
  tokens](#fees-in-other-tokens));
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

### Fees in other tokens

A pool's internal bribe holds its trading fees, and many pools pair a whitelisted token with one that has no Chainlink
feed. When an internal bribe's first two reward tokens are such a pair, and the gauge's pool is that pair's Algebra
base pool, the conduit also counts the other token's fees, up to the value of the whitelisted tokens in the same bribe.
An internal bribe therefore counts at most twice its whitelisted fees. External bribes count only whitelisted tokens.

The conduit prices the other token at the pool's average price over the last 30 minutes, read from the pool's plugin,
and converts it with the whitelisted token's Chainlink price. Trades in the vote's own block don't move that average.
The other token counts as zero if the plugin's answer is malformed or takes more than 120,000 gas (`TWAP_GAS`), or if
the average is too extreme to be a real price (`TICK_EDGE`), as it is in a pool stuck at the end of its range.

### Claiming

`claim(tokenId, feeAddresses, bribeAddresses, tokens)` claims `tokens` for an opted-in veNFT from the given fee and
bribe contracts. For each token, the conduit sends 1% of what it received, rounded down, to the treasury and the rest
to the veNFT's owner, and returns the amounts claimed. Anyone can call it, for any token, and the fee is the same
whoever calls. At least one fee or bribe contract is required.

The conduit also records, for each veNFT, the block of its last claim that received anything:
`lastClaimBlock(tokenId)`. Each `Claimed` event carries the block recorded before it as `previousClaimBlock`, so a
veNFT's claims can be read newest first, one block of logs at a time: start at `lastClaimBlock(tokenId)` and follow
`previousClaimBlock` back. When a block holds several claims for the same veNFT, the first one that received anything
points to the previous block and the later ones point to the block itself, so follow the smallest
`previousClaimBlock` below the current block. Claims that receive nothing don't move the pointer. The chain follows
the veNFT across owners, and each event names the owner at the time.

## For veNFT holders

To opt in, call `setConduitApproval(0x692c323B425A9DfeebE302F56168a7798D93EAC5, tokenId, true)` on the Hydrex
VotingEscrow. This delegates your veNFT's votes to the conduit from the next epoch and lets the conduit claim your
rewards. Call it with `false` to opt out. Transferring the veNFT clears the claim approval, so a new owner has to opt
in again. A veNFT has one delegate, so opting in to version 2 takes it out of version 1.

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

`score`, `currentScore` and `poolValue` use the same numbers as `vote`, except in the gas case described under
[Trust and limitations](#trust-and-limitations). Like `vote`, they revert with `EpochStale` until someone calls
`update_period()` on the Hydrex minter at the start of an epoch, with `NoVotingPower` if the conduit had no delegated
votes when the epoch started, and with `SequencerDown` while the sequencer is down or in the hour after it comes back.
The Voter accepts one vote per block. Replacing a vote of 20 pools with 20 others costs up to about 13M gas, and never
more than about 15.8M whatever the pools' plugins do, within Base's limit of 16,777,216 gas per transaction.

### Claiming rewards

For an opted-in veNFT, find the fee and bribe contracts where `earned(tokenId, token)` is positive. The first time
you claim for a veNFT, or after a long gap, pass only the contracts that owe each token, for example by claiming one
token at a time. `claim` asks every contract for every token, and a bribe walks back up to 50 epochs for any token it
hasn't paid recently. After that, a combined claim is cheap. A bribe never looks back more than 50 epochs, so after a
longer gap you may need to claim more than once.

Leave out any token that can't currently be sent to the treasury or the owner, such as USDC to a blocklisted
address: it makes the whole claim revert.

## Trust and limitations

- Nobody can change the conduit. A new treasury, fee or price feed means a new deployment, and holders opting in
  again. The only thing it writes after deployment is the block of each veNFT's last claim.
- Hydrex's Voter, VotingEscrow and bribes are upgradeable, so the conduit is only as safe as they are.
- The bribes' owner, `0x1aE3753d9b60743A89159CcFF8E251C60B560311`, can deposit a bribe, win the vote with it and take
  the bribe back, or take any bribe's tokens. Nobody else can.
- Chainlink prices only affect votes. If a feed goes stale, its token counts as zero in both the vote in force and
  the proposal, so a worse proposal can win while it lasts; for WETH and cbBTC, that takes 25 minutes without an
  update. If the sequencer feed stops answering, votes stop, but claims still work.
- Fees in other tokens are priced by the pools themselves, and trades in earlier blocks can move a pool's average a
  long way: holding a thin pool at the end of its range for one minute moves its 30-minute average about 50-fold.
  That is cheap in a thin pool, and free for whoever controls a token's supply. The cap limits the damage: what
  delegators receive from a pool is always at least half of what the conduit counts for it. Until someone proposes
  again, a pushed-down price can let a worse proposal win, and a pushed-up price can keep a worse vote in force.
- Algebra's factory owner, `0x74266f2b206D1359B83fc74949EF07176FB3AE03`, and its administrator,
  `0xDeaD1F5aF792afc125812E875A891b038f888258`, can replace a pool's plugin, change its configuration, or upgrade
  the upgradeable plugins, and the owner can give those rights to others. A broken or hostile plugin can make a pool's
  other-token fees count up to the cap, or not at all, but it gets at most `TWAP_GAS` per call, so it can't make a
  vote too expensive to send. Anyone can replace the plugin of an Algebra custom pool they create, so only a pair's
  base pool counts.
- A plugin read that needs more than `TWAP_GAS` counts as zero, and a read costs less when its storage is already
  warm, for example through an access list. So a plugin that needs about that much can count in one call and not in
  another, and `score`, `currentScore` and `poolValue` can then disagree with `vote`. The heaviest plugin on Base needs
  about 104,000 gas.
- Scores use other voters' current votes. If they change theirs later, the vote in force may no longer be the best,
  and anyone can propose a better one. A vote accepted in an epoch's last block can't be replaced.
- A token that charges a fee on transfers is charged twice on its way through the conduit.
- Tokens sent to the conduit by mistake are stuck there.
- The Voter calls whatever fee and bribe contracts a claim lists, so anyone can claim dust through a contract of their
  own. Each such claim adds to a veNFT's claim history, and someone willing to pay for a claim in every block can make
  the history as long as they like. Readers should expect claims of unknown tokens or tiny amounts, and may want to
  limit how far back they walk.

## Deployment

Deployed on 2026-10-20 by transaction
[`0x70ad…0eba`](https://basescan.org/tx/0x70addba92788cc910826cbcbfe266168e95c4f63e37913bbe5d7e86db9000eba).
The source is verified on [BaseScan](https://basescan.org/address/0x692c323B425A9DfeebE302F56168a7798D93EAC5#code) and
[Sourcify](https://repo.sourcify.dev/8453/0x692c323B425A9DfeebE302F56168a7798D93EAC5) as an exact match.

| | |
|---|---|
| Network | Base |
| Address | `0x692c323B425A9DfeebE302F56168a7798D93EAC5` |
| Voter | `0xc69E3eF39E3fFBcE2A1c570f8d3ADF76909ef17b` |
| VotingEscrow | `0x25B2ED7149fb8A05f6eF9407d9c8F878f59cd1e1` |
| Sequencer uptime feed | `0xBCF85224fc0756B9Fa45aA7892530B47e10b6433` |
| Algebra factory | `0x36077D39cdC65E1e3FB65810430E5b2c4D5fA29E` |
| Priced tokens | the whitelist above |
| Treasury | `0x450c72de8c0079B49AcedF294a13011bd09D125B`, a 2-of-3 Safe, fixed in the source |
| Fee | 1% (`FEE_BPS = 100`), fixed in the source |
| Method | CREATE2 through `0x4e59b44847b379578588920cA78FbF26c0B4956C`, salt `keccak256("metadex.cafe/ImmutableVeTokenConduit/v2")` |

Version 1 was deployed on 2026-10-19 by transaction
[`0x3fb9…4c00`](https://basescan.org/tx/0x3fb98ef128fcda6d9a59ac2d6b293b4ae2ccdb6e1c634d53651a0761867c4d00), with salt
`keccak256("metadex.cafe/ImmutableVeTokenConduit/v1")`, and is verified on BaseScan as an exact match. Its source is at
commit `c83a8d1`.

Deployment steps:

1. Install Foundry v1.8.5, the version CI uses, with `foundryup --install v1.8.5`. Another version can compile
   different bytecode.
2. Run `forge test` with `BASE_RPC_URL` set, then `script/check-verification.sh`.
3. Do a dry run with `forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL`, and check that it logs the address
   in the table above.
4. Deploy, then verify the contract on Basescan and Sourcify:

```
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast --ledger
ARGS=$(jq -j .deployment.constructorArgs verification/bytecode-hashes.json)
forge verify-contract 0x692c323B425A9DfeebE302F56168a7798D93EAC5 src/ImmutableVeTokenConduit.sol:ImmutableVeTokenConduit --chain base \
  --constructor-args $ARGS --license-type MIT --watch
```

## Verification

To check that the deployed contract is this repository's code, compare its code hash with the one recorded in
`verification/bytecode-hashes.json`, which `script/check-verification.sh` checks against a build of this repository:

```
cast keccak $(cast code 0x692c323B425A9DfeebE302F56168a7798D93EAC5 --rpc-url $BASE_RPC_URL)
jq -j .deployment.runtimeKeccak verification/bytecode-hashes.json
```

## Development

You need [Foundry](https://getfoundry.sh). The fork tests and some scripts also need a Base archive RPC in
`BASE_RPC_URL`.

- `forge test` runs the unit tests, and the fork tests too when `BASE_RPC_URL` is set. The fork tests run against
  Base at the block recorded in [`test/fixtures/fork.json`](test/fixtures/fork.json).
- `test/fixtures/generate.py [block]` rewrites that fixture.
- `script/check-signatures.sh` checks the interfaces in `src/interfaces/` against the Hydrex and Algebra sources
  vendored in `test/upstream/`.
- `script/check-verification.sh` checks that `verification/` matches the build.
- `script/refresh-verification.sh` regenerates `verification/` after a change to the source or the deploy script.

[`test/upstream/UPSTREAM.md`](test/upstream/UPSTREAM.md) records the Hydrex and Algebra contracts and the Chainlink
feeds the conduit is written against, and the behaviour it relies on.

The contract compiles with solc 0.8.37 for `prague`, via-IR, with 1,000,000 optimizer runs. Builds are reproducible.

## License

MIT. `REUSE.toml` records the copyright and license of every file.
