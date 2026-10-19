<!--
SPDX-FileCopyrightText: 2026 Léo de Souza
SPDX-License-Identifier: MIT
-->

# hydrex-conduit

`ImmutableVeTokenConduit` is a Hydrex conduit that nobody controls. veNFT holders delegate their votes to it. Anyone
can propose how it votes, and the contract accepts a proposal only if it expects the proposal to pay the delegators
more. Anyone can claim a delegator's rewards through it. The rewards are swapped to USDC and paid to the veNFT's
owner, less a 1% fee paid to a fixed treasury.

There are no roles, no setters and no upgrade path. The treasury, the fee, the routers, the price feeds and the
Hydrex contracts are fixed when the contract is deployed.

The whole contract is [`src/ImmutableVeTokenConduit.sol`](src/ImmutableVeTokenConduit.sol). Its integration with
Hydrex's Voter and VotingEscrow follows Hydrex's own `VeTokenConduit`; no code is copied from it.

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

Only these tokens count in votes, and only they can be claimed by third parties:

| Token | Chainlink feed | Heartbeat | Maximum age |
|---|---|---|---|
| WETH | ETH / USD `0x50015f8b17fb2C290Dde41fDc246ed0dcEE93a8b` | 1,200 s | 1,500 s |
| cbBTC | cbBTC / USD `0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D` | 1,200 s | 1,500 s |
| USDC | USDC / USD `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` | 86,400 s | 108,000 s |
| EURC | EURC / USD `0xDAe398520e2B67cd3f27aeF9Cf14D93D927f8250` | 86,400 s | 108,000 s |

All four feeds are in Chainlink's "low" risk category. The maximum age is each feed's heartbeat plus 25%. In votes, a
token whose feed is stale, reverts or answers zero or less counts as zero. Other tokens are left out:

- HYDX, BNKR, kVCM and the wrapped stocks have no Chainlink feed on Base.
- VVV's feed is in Chainlink's "new" category.
- SOL, USDT and USD₮0 are bridged tokens whose feeds price the underlying asset. If a bridge failed, they would still
  count at full value.

Votes, and claims by anyone but the owner, revert while Chainlink's sequencer uptime feed
(`0xBCF85224fc0756B9Fa45aA7892530B47e10b6433`) reports Base's sequencer down, or within an hour of it coming back.

## How claims work

`claim(tokenId, feeAddresses, bribeAddresses, claimTokens, swaps, minUsdcOut)` can be called by anyone, for any veNFT
whose owner has opted in. The Voter refuses the claim otherwise.

1. The conduit claims `claimTokens` from the given fee and bribe contracts to itself.
2. It swaps every claimed token other than USDC through a fixed router (KyberSwap's MetaAggregationRouterV2). Each
   swap is approved for exactly the claimed amount, and the approval is reset to zero afterwards. A claimed token
   left unswapped makes the claim revert. USDC is never approved.
3. It takes 1% of the USDC received (`FEE_BPS = 100`) for `TREASURY`, and sends the rest to `ownerOf(tokenId)`. There
   is no recipient parameter, and the conduit holds nothing after the transaction.

When the caller is not the owner, every claimed token must be whitelisted with a fresh feed, and the USDC received
must be at least the Chainlink value of everything claimed, USDC included, less 1% (`MAX_SLIPPAGE_BPS`). This floor
is what stops a caller from routing a holder's rewards through a bad swap or sending the output elsewhere.
`claimFloor(tokens, amounts)` returns the same floor, so callers can size their routes first.

When the caller is the owner, any token can be claimed, no feed is read, and only the owner's own `minUsdcOut`
applies. The 1% fee applies to every claim through the conduit, whoever calls it.

The conduit works on balance changes. Tokens sent to it by mistake are neither paid out nor taken; they stay there.

## Trust model

| Who | Can | Cannot |
|---|---|---|
| Anyone | propose a vote, accepted only if it scores at least $1 higher; claim any opted-in veNFT's whitelisted rewards, paid to its owner, within 1% of their Chainlink value | make the vote score worse; redirect rewards; claim another holder's tokens that have no feed |
| Treasury (`TREASURY`) | receive the fee | anything else |
| Holder | claim any of their rewards through the conduit, or directly from the Voter without the fee | |

Nobody can change the treasury, the fee, the routers, USDC or the whitelist.

What remains trusted:

- **Hydrex.** The Voter, the VotingEscrow and the bribe beacon are upgradeable.
- **The bribes' owner**, `0x1aE3753d9b60743A89159CcFF8E251C60B560311`, which also owns the bribe factory. It can
  deposit a bribe, win the vote with it and take it back in the same transaction, or take any bribe's tokens.
  `test/Vote.t.sol` shows that nobody else can.
- **Chainlink**, for prices and the sequencer status.
- **Circle**, which could block USDC transfers to the treasury or to an owner.
- **KyberSwap's router**, whose output the floor checks for third-party claims but not for an owner's own claims.

## Opting in

A holder opts in with `setConduitApproval(conduit, tokenId, true)` on the VotingEscrow. This delegates the veNFT's
votes to the conduit and lets the conduit claim its rewards. From then on anyone can claim the holder's whitelisted
rewards through the conduit, at any time, and the holder pays the 1% fee on each such claim. The delegated votes
count from the next epoch.

`setConduitApproval(conduit, tokenId, false)` undoes both. Transferring the veNFT clears the claim approval, so a new
owner has to opt in again.

## Proposing and claiming

Any funded address can propose or claim.

- **Proposing.** Read `poolValue(pool)` and the Voter's `weights(pool)` for the pools that pay, and compute the
  allocation that maximises the score over at most 20 pools: the optimum gives pool `i` about
  `sqrt(B_i × V_i / λ) − V_i` votes, with `λ` set so that the votes add up to the conduit's power. Check it with
  `score(pools, weights)` and an `eth_call` to `vote`, then send it. The Voter takes one vote per block.
- **Claiming.** For an opted-in veNFT, find the fee and bribe contracts whose `earned(tokenId, token)` is positive,
  fetch a KyberSwap route to USDC for each exact amount with the conduit as sender and recipient, check the total
  against `claimFloor`, simulate, and send.
- **Holders** can claim tokens without a feed themselves through `claim`, with their own `minUsdcOut`, or skip the
  conduit and claim from the Voter.

## Deployment

Not deployed yet.

| | |
|---|---|
| Network | Base |
| `voter` | `0xc69E3eF39E3fFBcE2A1c570f8d3ADF76909ef17b`, Hydrex Voter |
| `veToken` | `0x25B2ED7149fb8A05f6eF9407d9c8F878f59cd1e1`, Hydrex VotingEscrow |
| `usdc` | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| `sequencerFeed` | `0xBCF85224fc0756B9Fa45aA7892530B47e10b6433` |
| `routers` | `[0x6131B5fae19EA4f9D964eAc0408E4408b66337b5]` |
| `pricedTokens` | the whitelist above |
| `TREASURY` | `0x450c72de8c0079B49AcedF294a13011bd09D125B`, a Safe (2 of 3), in the source |
| `FEE_BPS` | `100`, in the source |
| Method | CREATE2 through the default deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C` |
| Salt | `keccak256("metadex.cafe/ImmutableVeTokenConduit/usdc/v1")` |
| Address | `0xAA21A117d74eA4E73154eB9Ad357CE562e60dFf9` |

Every constructor argument is a constant in `script/Deploy.s.sol`. The treasury and the fee are constants in the
source, so they are part of the bytecode hash and the address. The constructor checks that every feed answers and
the sequencer is up, and registers the conduit with the VotingEscrow (`setConduitApprovalConfig([3, 5], "")`:
claim-redirect approval and vote delegation).

```
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast --ledger
ARGS=$(jq -r .deployment.constructorArgs verification/bytecode-hashes.json)
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
  checks, a VotingEscrow, bribes, Chainlink feeds, ERC-20s that return nothing, act like USDT or block transfers, and
  routers that pull too much, pay too little, pay someone else or re-enter. The score is checked against a reference
  implementation on fuzzed inputs up to $10^30 of rewards and 10^30 votes, and an invariant test fuzzes claims with a
  malicious router and random callers.
- `BASE_RPC_URL=<archive rpc> forge test --match-path test/Fork.t.sol` runs against Base at the block recorded in
  [`test/fixtures/fork.json`](test/fixtures/fork.json). It opts in veNFT 14247, claims its real rewards as a stranger
  through a recorded KyberSwap route, claims HYDX as its owner, and moves to the next epoch to vote. There it
  recreates the recorded epoch's bribes and other voters' weights, proposes the water-filling allocation computed
  off chain by [`test/fixtures/generate.py`](test/fixtures/generate.py), and checks that the score matches it
  exactly. The worst case, a 20-pool proposal replacing a different 20-pool vote, uses about 9.9M gas, under the 14M
  the test allows and the 16.8M a Base transaction may use. CI runs it only when the `BASE_RPC_URL` secret is set.
- Builds are reproducible; `verification/` holds the standard JSON input and bytecode hashes, checked in CI.
- Compiler: solc 0.8.37, `prague`, optimizer 1,000,000 runs, via-IR, ipfs metadata.

## Known limitations

- Only the four whitelisted tokens count in votes, and only they can be claimed by third parties.
- A third-party claim can leave a holder up to 1% below the Chainlink value of the swapped tokens, plus Chainlink's
  update threshold (0.15% for ETH, 0.3% for cbBTC, USDC and EURC).
- A holder avoids the fee only by claiming directly from the Voter before someone claims through the conduit.
- At most 20 pools per vote, so that every accepted vote can be replaced within one transaction.
- The first proposal in the final block before an epoch ends takes the Voter's one vote for that block.
- Scores use the votes in place when a proposal is made. Other voters can change theirs afterwards, so the vote in
  force can become worse than another; anyone can then propose the better one.
- Nothing can be changed. A new treasury, fee, router or feed means a new deployment, and holders opting in again.
- If a feed is deprecated, its token counts as zero in votes and cannot be claimed by third parties. If the sequencer
  feed stops answering, votes and third-party claims stop; owners' own claims still work.
- If KyberSwap retires its router, swaps stop working; direct claims still work.
- If USDC transfers to the treasury are ever blocked, every claim through the conduit reverts; direct claims still
  work.
- Tokens without a USDC route must be claimed directly.
- Tokens sent to the conduit by mistake are stuck.
- Bribe contracts only look 50 epochs past a veNFT's last claim, so after a long gap several claims may be needed.

## License

MIT, REUSE compliant. The vendored Hydrex files are MIT and unmodified, with their copyright holder recorded in
`REUSE.toml`.
