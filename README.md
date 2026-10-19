# hydrex-conduit

`ImmutableVeTokenConduit` is a Hydrex conduit that nobody controls. veNFT holders delegate their votes to it. Anyone
can propose how it votes, and the contract accepts a proposal only if it expects the proposal to pay the delegators
more. Anyone can claim a delegator's rewards through it. Each claimed token is paid to the veNFT's owner, less a 1%
fee in the same token, paid to a fixed treasury.

There are no roles, no setters and no upgrade path. The treasury, the fee, the price feeds and the Hydrex contracts
are fixed when the contract is deployed.

The whole contract is [`src/ImmutableVeTokenConduit.sol`](src/ImmutableVeTokenConduit.sol).

## How votes are verified

`vote(pools, weights)` has the same signature as the Voter's. Anyone can call it. The contract scores the proposal and
the vote in force, and forwards the proposal to the Voter only if it scores at least $1 (`MIN_GAIN`) more. Otherwise
it reverts with `NotBetter`.

The score is the reward the delegators can expect this epoch, in 18-decimal USD:

    score = Σ B × x / (V + x)

For each pool:

- **B** is the USD value of the pool's bribes for this epoch: `rewardData(token, epoch).rewardsPerEpoch` on both the
  external and the internal bribe, for each whitelisted token, at its Chainlink price.
- **V** is the other voters' votes: the pool's weight this epoch, less the conduit's own votes if it has voted this
  epoch.
- **x** is the conduit's votes on the pool, rounded as the Voter rounds them: `weight × power / Σ weights`, where
  `power` is the conduit's voting power at the start of the epoch.

A pool whose gauge is dead counts zero, and a proposal that includes one reverts, because the Voter would silently
skip it. Votes do not carry over between epochs, so the first proposal of an epoch competes against a score of zero.
A proposal has between 1 and 20 pools (`MAX_POOLS`), with no duplicates and no zero weight.

`score`, `currentScore` and `poolValue` expose the same valuation as views, so a proposer can compute the best
allocation with exactly the contract's numbers and check it with `eth_call` before sending it.

### The whitelist

Only these tokens count in votes:

| Token | Chainlink feed | Heartbeat | Maximum age |
|---|---|---|---|
| WETH | ETH / USD `0x50015f8b17fb2C290Dde41fDc246ed0dcEE93a8b` | 1,200 s | 1,500 s |
| cbBTC | cbBTC / USD `0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D` | 1,200 s | 1,500 s |
| USDC | USDC / USD `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` | 86,400 s | 108,000 s |
| EURC | EURC / USD `0xDAe398520e2B67cd3f27aeF9Cf14D93D927f8250` | 86,400 s | 108,000 s |

All four feeds are in Chainlink's "low" risk category. The maximum age is each feed's heartbeat plus 25%. A token
whose feed is stale, reverts or answers zero or less counts as zero. Other tokens are left out:

- HYDX, BNKR, kVCM and the wrapped stocks have no Chainlink feed on Base.
- VVV's feed is in Chainlink's "new" category.
- SOL, USDT and USD₮0 are bridged tokens whose feeds price the underlying asset. If a bridge failed, they would still
  count at full value.

Votes revert while Chainlink's sequencer uptime feed (`0xBCF85224fc0756B9Fa45aA7892530B47e10b6433`) reports Base's
sequencer down, or within an hour of it coming back.

## How claims work

`claim(tokenId, feeAddresses, bribeAddresses, tokens)` can be called by anyone, for any veNFT whose owner has opted in.
It needs at least one fee or bribe contract, so the Voter always checks the opt-in, and refuses the claim otherwise.

1. The conduit records its balance of each token, then claims `tokens` from the given fee and bribe contracts to
   itself.
2. For each token in turn, the amount claimed is the conduit's balance less the recorded one. The conduit sends 1% of
   it (`FEE_BPS = 100`, rounded down) to `TREASURY`, and the rest to `ownerOf(tokenId)`. A token listed twice is paid
   once. There is no recipient parameter, and none of the claimed tokens stay in the conduit.

Nothing is swapped or priced, so any token can be claimed, by anyone, and claims read no feeds. The fee is the same
whoever calls. `claim` returns the amounts claimed, so callers can simulate it first.

## Trust model

| Who | Can | Cannot |
|---|---|---|
| Anyone | propose a vote, accepted only if it scores at least $1 higher; claim any opted-in veNFT's rewards, paid to its owner less 1% | make the vote score worse; redirect rewards |
| Treasury (`TREASURY`) | receive the fee | anything else |

What remains trusted:

- **Hydrex.** The Voter, the VotingEscrow and the bribe beacon are upgradeable.
- **The bribes' owner**, `0x1aE3753d9b60743A89159CcFF8E251C60B560311`, which also owns the bribe factory. It can
  deposit a bribe, win the vote with it and take it back in the same transaction, or take any bribe's tokens.
  `test/Fork.t.sol` checks on Base that nobody else can, directly or through the bribe factory, and
  `test/Vote.t.sol` plays out the attack.
- **Chainlink**, for prices and the sequencer status, in votes only.

## Opting in

A holder opts in with `setConduitApproval(conduit, tokenId, true)` on the VotingEscrow. This delegates the veNFT's
votes to the conduit and lets the conduit claim its rewards. The delegated votes count from the next epoch.

`setConduitApproval(conduit, tokenId, false)` undoes both. Transferring the veNFT clears the claim approval, so a new
owner has to opt in again.

## Proposing and claiming

Any funded address can propose or claim.

- **Proposing.** For each pool that pays, read `poolValue(pool)` as B and the Voter's `weights(pool)` as V, less
  `votes(conduit, pool)` if the conduit has voted this epoch (`lastVoted(conduit)` is at or after the epoch's start).
  Then compute the allocation that maximises the score over at most 20 pools: the optimum gives pool `i` about
  `sqrt(B_i × V_i / λ) − V_i` votes, with `λ` set so that the votes add up to the conduit's power. Check it with
  `score(pools, weights)` and an `eth_call` to `vote`, then send it. The Voter takes one vote per block.
- **Claiming.** For an opted-in veNFT, find the fee and bribe contracts whose `earned(tokenId, token)` is positive,
  and pass them with the tokens to `claim`.

## Deployment

Not deployed yet.

| | |
|---|---|
| Network | Base |
| `voter` | `0xc69E3eF39E3fFBcE2A1c570f8d3ADF76909ef17b`, Hydrex Voter |
| `veToken` | `0x25B2ED7149fb8A05f6eF9407d9c8F878f59cd1e1`, Hydrex VotingEscrow |
| `sequencerFeed` | `0xBCF85224fc0756B9Fa45aA7892530B47e10b6433` |
| `pricedTokens` | the whitelist above |
| `TREASURY` | `0x450c72de8c0079B49AcedF294a13011bd09D125B`, a Safe (2 of 3), in the source |
| `FEE_BPS` | `100`, in the source |
| Method | CREATE2 through the default deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C` |
| Salt | `keccak256("metadex.cafe/ImmutableVeTokenConduit/v1")` |
| Address | `0xF9BF355114CE4F9AEF13788a3F1ed9383F6541aF` |

Every constructor argument is a constant in `script/Deploy.s.sol`. The treasury and the fee are constants in the
source, so they are part of the bytecode hash and the address. The constructor takes one to four priced tokens,
checks that every feed answers and the sequencer is up, and registers the conduit with the VotingEscrow
(`setConduitApprovalConfig([3, 5], "")`: claim-redirect approval and vote delegation).

```
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast --ledger
ARGS=$(jq -j .deployment.constructorArgs verification/bytecode-hashes.json)
forge verify-contract <address> src/ImmutableVeTokenConduit.sol:ImmutableVeTokenConduit --chain base \
  --constructor-args $ARGS --license-type MIT --watch
forge verify-contract <address> src/ImmutableVeTokenConduit.sol:ImmutableVeTokenConduit --chain base \
  --verifier sourcify
```

Etherscan records the license separately from the SPDX header, hence `--license-type`; Sourcify reads it from the
source. After deploying, keep `broadcast/Deploy.s.sol/8453/run-latest.json`. After changing the source or
`script/Deploy.s.sol`, run `BASE_RPC_URL=<rpc> script/refresh-verification.sh`.

## Upstream pins

`test/upstream/` vendors the Hydrex interfaces and the bribe implementation the contract is written against, from
Sourcify; see [`UPSTREAM.md`](test/upstream/UPSTREAM.md), which also records the addresses, the feeds and the facts
about Hydrex the design depends on, each with its source line. `src/interfaces/` declares only the members the
contract uses and imports nothing. `script/check-signatures.sh` checks each Hydrex member against the vendored
declaration, `test/Selectors.t.sol` pins every selector, and `test/Fork.t.sol` pins the implementations and code
hashes on Base.

## Reviewing

- `src/` is the whole on-chain surface. The only external functions that change state are `vote` and `claim`, and the
  contract's storage is written only by the constructor (`test/Surface.t.sol`).
- `forge test` runs the unit suite against `test/mocks/`: a Voter that mirrors `VoterV5`'s vote, reset and claim
  checks, a VotingEscrow, bribes, Chainlink feeds, and ERC-20s that return nothing, return `false`, take a transfer
  tax, block transfers or re-enter. The score is checked against a reference implementation on fuzzed inputs up to
  $10^30 of rewards and 10^30 votes, and an invariant test fuzzes claims of several tokens by random callers.
- `BASE_RPC_URL=<archive rpc> forge test --match-path test/Fork.t.sol` runs against Base at the block recorded in
  [`test/fixtures/fork.json`](test/fixtures/fork.json). It deploys the conduit with the deploy script, opts in veNFT
  14247, and claims its real USDC, WETH and HYDX rewards as a stranger and as the owner. It then moves to the next
  epoch to vote, recreates the recorded epoch's bribes and other voters' weights, proposes the water-filling
  allocation computed off chain by [`test/fixtures/generate.py`](test/fixtures/generate.py), and checks that the
  score matches it exactly. The worst case, a 20-pool proposal replacing a different 20-pool vote, uses about 9.9M
  gas, under the 14M the test allows. CI runs it only when the `BASE_RPC_URL` secret is set.
- `BASE_RPC_URL=<archive rpc> test/fixtures/generate.py [block]` rewrites the fixture. It needs `cast`.
- Builds are reproducible; `verification/` holds the standard JSON input and bytecode hashes, checked in CI.
- Compiler: solc 0.8.37, `prague`, optimizer 1,000,000 runs, via-IR, ipfs metadata.

## Known limitations

- A token whose feed is stale or broken counts as zero in both the vote in force and the proposal. While that lasts,
  a proposal that moves votes away from that token's bribes can win even if it is worse in real terms. For WETH and
  cbBTC this takes more than 25 minutes without a Chainlink update. Reverting instead would stop votes for good if a
  feed were retired.
- Anyone can claim any of an opted-in holder's rewards at any time, in any token they choose, and the holder pays
  1% of each.
- A holder avoids the fee only by claiming directly from the Voter before someone claims through the conduit.
- A token that takes a cut of every transfer is taxed twice on its way through the conduit.
- A token that blocks transfers to the treasury or to the owner, as Circle can for USDC, makes any claim that
  includes it revert. Leave it out, or claim it directly.
- At most 20 pools per vote, so that every accepted vote can be replaced within one transaction.
- A vote accepted in an epoch's last block cannot be replaced: the Voter takes one vote per block.
- Scores use the votes in place when a proposal is made. Other voters can change theirs afterwards, so the vote in
  force can become worse than another; anyone can then propose the better one.
- Nothing can be changed. A new treasury, fee or feed means a new deployment, and holders opting in again.
- If the sequencer feed stops answering, votes stop; claims still work.
- Tokens sent to the conduit by mistake are stuck.
- Bribe contracts only look 50 epochs past a veNFT's last claim, so after a long gap several claims may be needed.

## License

MIT, REUSE compliant. `REUSE.toml` records every file's copyright holder. The vendored Hydrex files are MIT and
unmodified.
