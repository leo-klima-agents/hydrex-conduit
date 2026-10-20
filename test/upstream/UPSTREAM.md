# Upstream pins

Byte-identical copies of the Hydrex and Algebra files `src/interfaces/` is checked against. Nothing in `src/` imports
them and `foundry.toml` skips them. `script/check-signatures.sh` checks that every Hydrex and Algebra member declared in
`src/interfaces/` has the same signature here, and `test/Selectors.t.sol` pins every selector.

## Vendored files

| Local file | Upstream | License |
|---|---|---|
| `hydrex/voter/IVoterV5_Logic.sol` | Voter implementation, `contracts/VoterV5/IVoterV5_Logic.sol` | MIT |
| `hydrex/voter/IVoterV5_Storage.sol` | Voter implementation, `contracts/VoterV5/IVoterV5_Storage.sol` | MIT |
| `hydrex/voter/IVoterV5_ClaimLogic.sol` | Voter implementation, `contracts/VoterV5/IVoterV5_ClaimLogic.sol` | MIT |
| `hydrex/votingescrow/IVotingEscrowV2_Logic.sol` | VotingEscrow implementation, `contracts/VoterV5/VotingEscrow/IVotingEscrowV2_Logic.sol` | MIT |
| `hydrex/votingescrow/IVotes.sol` | VotingEscrow implementation, `contracts/VoterV5/VotingEscrow/interfaces/IVotes.sol` | MIT |
| `hydrex/bribe/BribeV2.sol` | Bribe implementation, `contracts/VoterV5/BribeV2.sol` | MIT |
| `algebra/core/IAlgebraFactory.sol` | Algebra factory, `contracts/interfaces/IAlgebraFactory.sol` | GPL-2.0-or-later |
| `algebra/core/IAlgebraPoolState.sol` | Algebra pool, `contracts/interfaces/pool/IAlgebraPoolState.sol` | GPL-2.0-or-later |
| `algebra/plugin/IVolatilityOracle.sol` | Hydrex base plugin, `contracts/interfaces/plugins/IVolatilityOracle.sol` | GPL-2.0-or-later |
| `algebra/upgradeable-plugin/IVolatilityOracle.sol` | Upgradeable plugin implementation, `@cryptoalgebra/volatility-oracle-plugin/contracts/interfaces/IVolatilityOracle.sol` | GPL-2.0-or-later |

| Implementation | Address | Sourcify | Compiler |
|---|---|---|---|
| Voter (`VoterV5` 5.4.4) | `0x9CB9fc7D128F89CBD43Bbfd89dBAb05D1FA17233` | [exact match](https://repo.sourcify.dev/8453/0x9CB9fc7D128F89CBD43Bbfd89dBAb05D1FA17233), 2026-06-10 | 0.8.13, 10 runs, via-IR |
| VotingEscrow (`VotingEscrowV2Upgradeable`) | `0x0FC68cE53Be957a1AA779f553AD49f6068fFf231` | [match](https://repo.sourcify.dev/8453/0x0FC68cE53Be957a1AA779f553AD49f6068fFf231), 2025-10-19 | 0.8.13, 200 runs |
| Bribe (`BribeV2` 2.1.0) | `0x6225a2b81f83a71c0595449a224fc2385dfaa28d` | [exact match](https://repo.sourcify.dev/8453/0x6225a2b81f83a71c0595449a224fc2385dfaa28d), 2025-09-22 | 0.8.13, 200 runs |
| Gauge logic (`VoterV5_GaugeLogic`) | `0x8CF73Eb543c75bA5f2e188D3ce5F8682f2E7f0A3` | [exact match](https://repo.sourcify.dev/8453/0x8CF73Eb543c75bA5f2e188D3ce5F8682f2E7f0A3), 2026-08-02 | 0.8.13, 200 runs |
| Algebra factory (`AlgebraFactory`, Algebra Integral) | `0x36077D39cdC65E1e3FB65810430E5b2c4D5fA29E` | [match](https://repo.sourcify.dev/8453/0x36077D39cdC65E1e3FB65810430E5b2c4D5fA29E), 2026-06-30 | 0.8.20, 1,000,000 runs |
| Algebra pool (`AlgebraPool`), WETH/TIBBIR's | `0xB3f0828eB3375B609b49E9Fb959472a29cD6E49a` | [match](https://repo.sourcify.dev/8453/0xB3f0828eB3375B609b49E9Fb959472a29cD6E49a), 2025-10-11 | 0.8.20, 0 runs |
| Plugin (`HydrexBasePlugin`), CREATOR/WETH's | `0x58d766bfBD60a02425E706596A0111E05Fd6092D` | [match](https://repo.sourcify.dev/8453/0x58d766bfBD60a02425E706596A0111E05Fd6092D), 2026-06-24 | 0.8.20, 200 runs |
| Upgradeable plugin implementation (`AlgebraUpgradeablePlugin`) | `0xAF11628e68e8bD45375560E549Ab8411FA034D4F` | [match](https://repo.sourcify.dev/8453/0xAF11628e68e8bD45375560E549Ab8411FA034D4F), 2026-05-05 | 0.8.20, 0 runs |
| Plugin factory implementation (`AlgebraUpgradeablePluginFactory`) | `0xde57C7d4d2E98DaFb7cDC59E9c88d28f543AE922` | [match](https://repo.sourcify.dev/8453/0xde57C7d4d2E98DaFb7cDC59E9c88d28f543AE922), 2026-02-19 | 0.8.20, 0 runs |
| Custom-pool entry point (`AlgebraCustomPoolEntryPoint`) | `0x00EdE53f39415E64c78eebD02AD9D383b3A0C0F1` | [match](https://repo.sourcify.dev/8453/0x00EdE53f39415E64c78eebD02AD9D383b3A0C0F1), 2026-06-21 | 0.8.20, 1,000,000 runs |

Sourcify has the VotingEscrow implementation and the Algebra contracts as a "match", not an "exact match": the bytecode
matches but the metadata hash differs, so comments in their sources may differ from what was compiled. Every gauged
Algebra pool runs the same pool code, with either its own `HydrexBasePlugin` (227 of the 238 gauged Algebra pools at
block 52,832,165) or a proxy to the upgradeable plugin implementation (the other 11). The vendored files are fetched
from Sourcify with the commands below, and `SHA256SUMS` holds their hashes:

```
for a in 0x9CB9fc7D128F89CBD43Bbfd89dBAb05D1FA17233 0x0FC68cE53Be957a1AA779f553AD49f6068fFf231 0x6225a2b81f83a71c0595449a224fc2385dfaa28d; do
  curl -sS "https://sourcify.dev/server/v2/contract/8453/$a?fields=sources" > /tmp/$a.json
done
V=/tmp/0x9CB9fc7D128F89CBD43Bbfd89dBAb05D1FA17233.json E=/tmp/0x0FC68cE53Be957a1AA779f553AD49f6068fFf231.json B=/tmp/0x6225a2b81f83a71c0595449a224fc2385dfaa28d.json
for f in IVoterV5_Logic IVoterV5_Storage IVoterV5_ClaimLogic; do
  jq -j ".sources[\"contracts/VoterV5/$f.sol\"].content" $V > test/upstream/hydrex/voter/$f.sol
done
jq -j '.sources["contracts/VoterV5/VotingEscrow/IVotingEscrowV2_Logic.sol"].content' $E > test/upstream/hydrex/votingescrow/IVotingEscrowV2_Logic.sol
jq -j '.sources["contracts/VoterV5/VotingEscrow/interfaces/IVotes.sol"].content' $E > test/upstream/hydrex/votingescrow/IVotes.sol
jq -j '.sources["contracts/VoterV5/BribeV2.sol"].content' $B > test/upstream/hydrex/bribe/BribeV2.sol
for a in 0x36077D39cdC65E1e3FB65810430E5b2c4D5fA29E 0xB3f0828eB3375B609b49E9Fb959472a29cD6E49a 0x58d766bfBD60a02425E706596A0111E05Fd6092D 0xAF11628e68e8bD45375560E549Ab8411FA034D4F; do
  curl -sS "https://sourcify.dev/server/v2/contract/8453/$a?fields=sources" > /tmp/$a.json
done
F=/tmp/0x36077D39cdC65E1e3FB65810430E5b2c4D5fA29E.json P=/tmp/0xB3f0828eB3375B609b49E9Fb959472a29cD6E49a.json
H=/tmp/0x58d766bfBD60a02425E706596A0111E05Fd6092D.json U=/tmp/0xAF11628e68e8bD45375560E549Ab8411FA034D4F.json
jq -j '.sources["contracts/interfaces/IAlgebraFactory.sol"].content' $F > test/upstream/algebra/core/IAlgebraFactory.sol
jq -j '.sources["contracts/interfaces/pool/IAlgebraPoolState.sol"].content' $P > test/upstream/algebra/core/IAlgebraPoolState.sol
jq -j '.sources["contracts/interfaces/plugins/IVolatilityOracle.sol"].content' $H > test/upstream/algebra/plugin/IVolatilityOracle.sol
jq -j '.sources["@cryptoalgebra/volatility-oracle-plugin/contracts/interfaces/IVolatilityOracle.sol"].content' $U > test/upstream/algebra/upgradeable-plugin/IVolatilityOracle.sol
(cd test/upstream && sha256sum -c SHA256SUMS)
```

## Addresses

`test/Fork.t.sol` checks each of these at block 52,817,047 (2026-10-19).

| Contract | Address | Code hash |
|---|---|---|
| Voter proxy | `0xc69E3eF39E3fFBcE2A1c570f8d3ADF76909ef17b` | `0xbdf20cb78c052fa6ad3cfe77fde23f9eea05a6f1f4087c07ecde2f274a2b36e1` |
| Voter implementation (ERC-1967 slot) | `0x9CB9fc7D128F89CBD43Bbfd89dBAb05D1FA17233` | `0x42618eac51788e20459a854690666979bd13bbe185e3323bd6d7dd59ee8a31b0` |
| VotingEscrow proxy | `0x25B2ED7149fb8A05f6eF9407d9c8F878f59cd1e1` | `0x96c3cd33e65424eb56bec90a4fb2ab41c16085b1afc0dcb37dcd412b666fb2d6` |
| VotingEscrow implementation (ERC-1967 slot) | `0x0FC68cE53Be957a1AA779f553AD49f6068fFf231` | `0xe6b54672ba85711eac5516d6ce09fe96cabe9cc3764a178e5d2f33a6241c2b42` |
| Voter claim logic (`claimLogic()`) | `0x68Ed6a9fd3fe6DB26dEf56641c3B251278d8C21D` | `0xff06fc1990ab09a31cf65c657fd15babd45a76ecf9a93f0b64d33e163e6cecf8` |
| VotingEscrow approval logic (`approvalLogic()`) | `0x4B0BC0889EB524Dbae36d409fF733851E9B4f63D` | `0xd1fab3adcd045439b72359a675665cb9f9267b32aebb140df865fc723681a930` |
| Bribe beacon | `0x5aeb9f88b66cd94f0ce50d139f9fc257b65411c2` | `0xaaa27093ce9a3136b77cbcbfbee1c26a564b1d2742bc57f916f1cafe5e41f956` |
| Bribe implementation (`implementation()`) | `0x6225a2b81f83a71c0595449a224fc2385dfaa28d` | `0x419b9ff2bbe35af4ba4fb135c4f4a2cc215e0c212196d0b0d5dbf7bb6f301055` |
| Bribe owner and bribe factory owner | `0x1aE3753d9b60743A89159CcFF8E251C60B560311` | |
| Minter proxy | `0xA7D64625F45548a19B2A19e28E7546bb2839003E` | |
| `TREASURY`, a Safe 1.5.0 proxy (2 of 3) | `0x450c72de8c0079B49AcedF294a13011bd09D125B` | `0x4e381985ca68b3e5d27b4425fa581c19cf33146d3f887a3cfca96f55528ea46f` |
| Algebra factory | `0x36077D39cdC65E1e3FB65810430E5b2c4D5fA29E` | `0x6f54720c3eb4326e8cf846308b98ab0c0d070a441ca11ba8cd00be0256af7084` |
| Algebra factory owner, and its only default admin | `0x74266f2b206D1359B83fc74949EF07176FB3AE03` | |
| Algebra custom-pool entry point, a pool administrator and the only `CUSTOM_POOL_DEPLOYER` | `0x00EdE53f39415E64c78eebD02AD9D383b3A0C0F1` | `0x200c23737ade01ef361202814d1fb721b9dc811cf5f4345875c99770384ec3b2` |
| Algebra pool and plugin factory administrator (`POOLS_ADMINISTRATOR_ROLE`, `ALGEBRA_BASE_PLUGIN_FACTORY_ADMINISTRATOR`), an EIP-7702 account | `0xDeaD1F5aF792afc125812E875A891b038f888258` | |
| Upgradeable plugin beacon | `0x106937fC03212A762be17D529893A32E47bA13a1` | `0x2105a3ca212415ea232cb45c3d9a073ea881378afadc776198c59f79d018f97e` |
| Upgradeable plugin implementation (`implementation()`) | `0xAF11628e68e8bD45375560E549Ab8411FA034D4F` | `0x51aab6d45348f1b652884dcf8e4eaf06c54de68760f64f8487c5d670fc3488e4` |
| Upgradeable plugin beacon owner, a plugin factory proxy | `0xa8dD4C05796801C734E99d5582E90e3a8bD88194` | |
| Plugin factory implementation (ERC-1967 slot) | `0xde57C7d4d2E98DaFb7cDC59E9c88d28f543AE922` | `0xdda4b448b3ffa656fa5fdf88c424df94489a500023f889669e8632767edba9e5` |
| Plugin factory proxy admin (ERC-1967 slot), owned by the Algebra factory owner | `0x2689EF6a746f1b253CD772Fb045a7563505bEd00` | `0x8b4085015bf2b807a59b2290edcd3886b049469b05572e4b9e1b7fc0e430d9c9` |
| USDC/VAULT, an Algebra pool priced at the end of the tick range | `0xa69256ea019648815B1a3CE1C83C0D00a288dfc7` | |
| A USDC ERC-4626 vault's gauged pool | `0xBEEFE94c8aD530842bfE7d8B397938fFc1cb83b2` | |

## Chainlink feeds

Checked against Chainlink's Base directory
([feeds-ethereum-mainnet-base-1.json](https://reference-data-directory.vercel.app/feeds-ethereum-mainnet-base-1.json),
the data behind [docs.chain.link](https://docs.chain.link/data-feeds/price-feeds/addresses?network=base)) on
2026-10-19. Every price feed is in the "low" risk category, and each returned a fresh round that day.
`test/Fork.t.sol` checks the description and decimals on chain.

| Token | Feed | Description | Decimals | Heartbeat | Deviation | Maximum age |
|---|---|---|---|---|---|---|
| WETH `0x4200000000000000000000000000000000000006` | `0x50015f8b17fb2C290Dde41fDc246ed0dcEE93a8b` | ETH / USD | 8 | 1,200 s | 0.15% | 1,500 s |
| cbBTC `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` | `0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D` | cbBTC / USD | 8 | 1,200 s | 0.3% | 1,500 s |
| USDC `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` | USDC / USD | 8 | 86,400 s | 0.3% | 108,000 s |
| EURC `0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42` | `0xDAe398520e2B67cd3f27aeF9Cf14D93D927f8250` | EURC / USD | 8 | 86,400 s | 0.3% | 108,000 s |
| | `0xBCF85224fc0756B9Fa45aA7892530B47e10b6433` | L2 Sequencer Uptime Status Feed | 0 | | | |

## Facts the design depends on

Line numbers in `VoterV5.sol` are in the Voter implementation's sources on Sourcify. The claim logic, gauge logic and
approval logic are separate contracts that the Voter and the VotingEscrow `delegatecall`. Line numbers in Algebra
files are in the sources on Sourcify of the contract named in the implementation table above.

1. **Epochs.** `_epochTimestamp()` returns `minter.active_period()`
   ([`VoterV5.sol`](https://repo.sourcify.dev/8453/0x9CB9fc7D128F89CBD43Bbfd89dBAb05D1FA17233) line 1044). Bribes
   key `rewardData` by the same `active_period()` ([`BribeV2.sol`](hydrex/bribe/BribeV2.sol#L365-L374)).
2. **Voting power.** `_vote` uses `getPastVotes(voter, _epochTimestamp())` (`VoterV5.sol` line 698), so votes
   delegated during an epoch count only from the next one. Each pool gets
   `_voteProportions[i] * _weight / _totalVoteProportions` (line 712), where the total counts only live gauges
   (line 704), and a dead gauge is skipped (line 711).
3. **One vote per block.** `VOTE_DELAY` is set to 0 (`VoterV5.sol` line 174; the fork test reads it) and is enforced
   with `currentTime > lastVoted[_voter] + VOTE_DELAY` (line 748), and `vote` sets `lastVoted` to `block.timestamp`
   (line 691). A voter votes or resets at most once per block.
4. **Votes reset first.** `_vote` calls `_reset` (`VoterV5.sol` line 695), which loops over every pool of the
   previous vote and withdraws from both of its bribes (lines 635-666). The cost of a vote grows with the size of the
   one it replaces. Last epoch's `votes` stay in storage until then, but only this epoch's are in `weights`
   (lines 640, 650, 1024-1027).
5. **Killed gauges.** `killGauge` zeroes the pool's weight for the epoch (`VoterV5.sol` lines 590-594) and leaves
   `votes` and the bribes' deposits as they are. Bribes pay each epoch by their own deposits
   ([`BribeV2.sol`](hydrex/bribe/BribeV2.sol#L242-L284)), so voters keep earning a killed pool's bribes for that
   epoch until `_reset` withdraws them, which it does even for a killed gauge (`VoterV5.sol` lines 657-658).
6. **Deposits.** `notifyRewardAmount` credits the current epoch and has no withdrawal for the depositor
   ([`BribeV2.sol`](hydrex/bribe/BribeV2.sol#L357-L377)). Anyone can call it, for any of the bribe's reward tokens
   (line 358), on fee bribes as well as paid bribes. Fee bribes also list WETH, USDC, USDT, HYDX and oHYDX.
7. **Recovery.** `recoverERC20AndUpdateData` and `emergencyRecoverERC20` are `onlyAllowed`: the bribe's owner or its
   bribe factory ([`BribeV2.sol`](hydrex/bribe/BribeV2.sol#L402-L449)). The factory exposes both only to its own
   owner ([`BribeFactoryV4`](https://basescan.org/address/0x25f4d95ae6734b517675cbe863cf91879964b970#code)
   lines 255-274), which is the same address as the bribes' owner. `test/Fork.t.sol` checks that nobody else can call
   any of the four.
8. **Claims by token ID.** `claimBribesToRecipientByTokenId` and `claimFeesToRecipientByTokenId` require
   `isApprovedClaimRedirectOrOwner(msg.sender, tokenId)`
   ([`VoterV5_ClaimLogic`](https://basescan.org/address/0x68Ed6a9fd3fe6DB26dEf56641c3B251278d8C21D#code) lines 153
   and 188), which is true for the owner and for the token's claim-redirect address
   ([`VotingEscrowV2Upgradeable.sol`](https://repo.sourcify.dev/8453/0x0FC68cE53Be957a1AA779f553AD49f6068fFf231)
   lines 726-745). They then call whatever fee and bribe contracts the caller lists (lines 155 and 190), and bribes
   pay `_recipient` ([`BribeV2.sol`](hydrex/bribe/BribeV2.sol#L336-L339)). So the conduit can claim only for
   opted-in veNFTs, and an owner can always claim directly. A transfer clears the claim-redirect address
   (`VotingEscrowV2Upgradeable.sol` line 161).
9. **Opting in.** `setConduitApprovalConfig` registers the caller once, with a non-empty list of actions
   ([`VotingEscrowV2_ApprovalLogic`](https://repo.sourcify.dev/8453/0x4B0BC0889EB524Dbae36d409fF733851E9B4f63D)
   lines 23-39). Actions 3 and 5 are `CLAIM_REDIRECT_APPROVAL` and `VOTING_DELEGATE`
   (`IVotingEscrowV2_Data.sol` lines 28-36). `setConduitApproval(conduit, tokenId, true)` checks that the caller owns
   the token and runs both (lines 47-62, 130-163); `false` clears the claim-redirect address and delegates back to
   the owner.
10. **A fee bribe's pair.** Gauge creation passes the pool's two tokens to the bribe factory for both bribes
    ([`VoterV5_GaugeLogic`](https://repo.sourcify.dev/8453/0x8CF73Eb543c75bA5f2e188D3ce5F8682f2E7f0A3) lines 311 and 318). On chain,
    `rewardTokens(0)` and `rewardTokens(1)` of 416 of the 419 pair gauges' fee bribes are the pool's `token0` and
    `token1` (at block 52,832,165; the other three are Uniswap v4 pools of native ETH), and a bribe only appends to
    its list ([`BribeV2.sol`](hydrex/bribe/BribeV2.sol#L382-L399)). A single-asset vault gauge's fee bribe lists its
    asset, then another reward token. The conduit doesn't rely on this: it counts a tail only when the two tokens'
    base pool is the gauge's pool.
11. **Algebra pairs.** Anyone can create an Algebra pool ([`AlgebraFactory.sol`](https://repo.sourcify.dev/8453/0x36077D39cdC65E1e3FB65810430E5b2c4D5fA29E)
    line 100). `poolByPair` maps a pair, in either order, to its one base pool, set when the pool is created, and
    `token0` is the lower address (lines 116-151). An incentive-campaign gauge must be its pair's base pool
    (`VoterV5_GaugeLogic` lines 205-213), and needs Hydrex's pool eligibility oracle unless a gauge admin creates it
    (lines 236-249).
12. **Timepoints.** Both plugins write a timepoint from the pool's current tick in `beforeSwap`, at most once per
    block ([`HydrexBasePlugin.sol`](https://repo.sourcify.dev/8453/0x58d766bfBD60a02425E706596A0111E05Fd6092D) line 88 and
    `VolatilityOraclePlugin.sol` lines 85-94; [`AlgebraUpgradeablePlugin.sol`](https://repo.sourcify.dev/8453/0xAF11628e68e8bD45375560E549Ab8411FA034D4F)
    line 196 and `VolatilityOraclePluginImplementation.sol` lines 27-31). The pool calls `beforeSwap` before it
    computes either kind of swap ([`AlgebraPool.sol`](https://repo.sourcify.dev/8453/0xB3f0828eB3375B609b49E9Fb959472a29cD6E49a) lines 250,
    332 and 391-401), unless the plugin itself is swapping or the pool's plugin config clears the before-swap flag.
    `getTimepoints` extrapolates past the last timepoint with the pool's current tick (`VolatilityOracle.sol` line
    119). So a window that ends at the current block contains no tick set in it: the block's first swap records the
    tick from before it, and until then the pool's current tick is the one the previous block left.
13. **Plugin administration.** Only the Algebra factory's owner or a pool administrator can replace a pool's plugin
    (`AlgebraPool.sol` lines 472-474 and 497-501). They and the plugin itself can change its plugin config (lines
    504-511). Neither plugin's code clears the before-swap flag: each only resets its default config, which has it, or
    sets flags of it, or clears the after-swap flag (`HydrexBasePlugin.sol` lines 39, 67 and 115,
    `VolatilityOraclePlugin.sol` line 50 and `FarmingProxyPlugin.sol` lines 58 and 78; `AlgebraUpgradeablePlugin.sol`
    lines 135, 178 and 245 and `FarmingProxyPluginImplementation.sol` lines 53-59).
    One pool administrator is Algebra's custom-pool entry point, the factory's only `CUSTOM_POOL_DEPLOYER`
    (`AlgebraFactory.sol` lines 105-114). Anyone can create a custom pool through it, then replace that pool's plugin
    or change its config, but only on a pool that `customPoolByPair(msg.sender, token0, token1)` returns
    ([`AlgebraCustomPoolEntryPoint.sol`](https://repo.sourcify.dev/8453/0x00EdE53f39415E64c78eebD02AD9D383b3A0C0F1)
    lines 26-36, 69-76 and 83-87). A custom pool's address comes from a different CREATE2 salt than its pair's base
    pool, and `poolByPair` only holds base pools (`AlgebraFactory.sol` lines 88-97, 121 and 150-151), so the entry
    point can't act on a pool the conduit counts. The upgradeable plugins follow a beacon owned by a plugin factory,
    which upgrades it for the Algebra factory's owner and holders of its `ALGEBRA_BASE_PLUGIN_FACTORY_ADMINISTRATOR`
    role ([`AlgebraUpgradeablePluginFactory.sol`](https://repo.sourcify.dev/8453/0xde57C7d4d2E98DaFb7cDC59E9c88d28f543AE922)
    lines 56-60 and 242-244). The plugin factory is itself a proxy, administered by a proxy admin that the Algebra
    factory's owner owns. The upgradeable plugins delegate their oracle to a separate implementation
    (`VolatilityOracleConnector.sol` line 41). `test/Fork.t.sol` pins the factory's roles and the plugin factory's
    administration, and checks that a stranger can't replace a plugin, that a custom pool's deployer can't touch a
    base pool, and that a replaced plugin only stops the tail from counting.
14. **Storage.** `rewardData` is at slot 53 of a bribe's storage. `test/Fork.t.sol` writes it to replay deposits of
    tokens it can't mint, and checks the slot against a real deposit.

## Selectors

`test/Selectors.t.sol` checks every row. `setConduitApprovalConfig` takes an enum array, which the ABI encodes as
`uint8[]`.

| Member | Selector | Declared in |
|---|---|---|
| `vote(address[],uint256[])` | `0x6f816a20` | `IVoterV5_Logic.sol` |
| `_epochTimestamp()` | `0xf8803bb6` | `IVoterV5_Logic.sol` |
| `weights(address)` | `0xa7cac846` | `IVoterV5_Logic.sol` |
| `poolVoteLength(address)` | `0x8daeaa5a` | `IVoterV5_Logic.sol` |
| `gauges(address)` | `0xb9a09fd5` | `IVoterV5_Storage.sol` |
| `isAlive(address)` | `0x1703e5f9` | `IVoterV5_Storage.sol` |
| `external_bribes(address)` | `0xae21c4cb` | `IVoterV5_Storage.sol` |
| `internal_bribes(address)` | `0xeae40f26` | `IVoterV5_Storage.sol` |
| `votes(address,address)` | `0xcad1b906` | `IVoterV5_Storage.sol` |
| `poolVote(address,uint256)` | `0xc48f5af4` | `IVoterV5_Storage.sol` |
| `lastVoted(address)` | `0x9a61df89` | `IVoterV5_Storage.sol` |
| `claimBribesToRecipientByTokenId(address[],address[][],uint256,address)` | `0xa5f00340` | `IVoterV5_ClaimLogic.sol` |
| `claimFeesToRecipientByTokenId(address[],address[][],uint256,address)` | `0x11d41550` | `IVoterV5_ClaimLogic.sol` |
| `getPastVotes(address,uint256)` | `0x3a46b1a8` | `IVotes.sol` |
| `setConduitApprovalConfig(uint8[],string)` | `0x7c3a328f` | `IVotingEscrowV2_Logic.sol` |
| `ownerOf(uint256)` | `0x6352211e` | ERC-721 |
| `rewardData(address,uint256)` | `0x38174862` | `BribeV2.sol`, a public mapping of `Reward` |
| `totalSupplyAt(uint256)` | `0x981b24d0` | `BribeV2.sol` |
| `rewardTokens(uint256)` | `0x7bb7bed1` | `BribeV2.sol`, a public array |
| `poolByPair(address,address)` | `0xd9a641e1` | `IAlgebraFactory.sol` |
| `plugin()` | `0xef01df4f` | `IAlgebraPoolState.sol` |
| `getTimepoints(uint32[])` | `0x9d3a5241` | `IVolatilityOracle.sol` |
| `balanceOf(address)` | `0x70a08231` | ERC-20 |
| `transfer(address,uint256)` | `0xa9059cbb` | ERC-20 |
| `decimals()` | `0x313ce567` | ERC-20, Chainlink |
| `latestRoundData()` | `0xfeaf968c` | Chainlink |

## Refreshing

The Voter, VotingEscrow and bribe beacon are upgradeable, and Algebra pools' plugins can be replaced or upgraded. If
one changes, `test/Fork.t.sol` still passes at its pinned block, so check the new implementation by hand: vendor its
files, run `script/check-signatures.sh` and the fork test at a newer block, and re-check the facts above. A changed
fact may need a new deployment.
