# Upstream pins

Byte-identical copies of the Hydrex files `src/interfaces/` is checked against. Nothing in `src/` imports them and
`foundry.toml` skips them. `script/check-signatures.sh` checks that every Hydrex member declared in `src/interfaces/`
has the same signature here, and `test/Selectors.t.sol` pins every selector.

## Vendored files

| Local file | Upstream | License |
|---|---|---|
| `hydrex/voter/IVoterV5_Logic.sol` | Voter implementation, `contracts/VoterV5/IVoterV5_Logic.sol` | MIT |
| `hydrex/voter/IVoterV5_Storage.sol` | Voter implementation, `contracts/VoterV5/IVoterV5_Storage.sol` | MIT |
| `hydrex/voter/IVoterV5_ClaimLogic.sol` | Voter implementation, `contracts/VoterV5/IVoterV5_ClaimLogic.sol` | MIT |
| `hydrex/votingescrow/IVotingEscrowV2_Logic.sol` | VotingEscrow implementation, `contracts/VoterV5/VotingEscrow/IVotingEscrowV2_Logic.sol` | MIT |
| `hydrex/votingescrow/IVotes.sol` | VotingEscrow implementation, `contracts/VoterV5/VotingEscrow/interfaces/IVotes.sol` | MIT |
| `hydrex/bribe/BribeV2.sol` | Bribe implementation, `contracts/VoterV5/BribeV2.sol` | MIT |

| Implementation | Address | Sourcify | Compiler |
|---|---|---|---|
| Voter (`VoterV5` 5.4.4) | `0x9CB9fc7D128F89CBD43Bbfd89dBAb05D1FA17233` | [exact match](https://repo.sourcify.dev/8453/0x9CB9fc7D128F89CBD43Bbfd89dBAb05D1FA17233), 2026-06-10 | 0.8.13, 10 runs, via-IR |
| VotingEscrow (`VotingEscrowV2Upgradeable`) | `0x0FC68cE53Be957a1AA779f553AD49f6068fFf231` | [match](https://repo.sourcify.dev/8453/0x0FC68cE53Be957a1AA779f553AD49f6068fFf231), 2025-10-19 | 0.8.13, 200 runs |
| Bribe (`BribeV2` 2.1.0) | `0x6225a2b81f83a71c0595449a224fc2385dfaa28d` | [exact match](https://repo.sourcify.dev/8453/0x6225a2b81f83a71c0595449a224fc2385dfaa28d), 2025-09-22 | 0.8.13, 200 runs |

Sourcify has the VotingEscrow implementation as a "match", not an "exact match": the bytecode matches but the
metadata hash differs, so comments in its sources may differ from what was compiled. The vendored files are fetched
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

Line numbers in `VoterV5.sol` are in the Voter implementation's sources on Sourcify. The claim logic and approval
logic are separate contracts that the Voter and the VotingEscrow `delegatecall`.

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
   ([`BribeV2.sol`](hydrex/bribe/BribeV2.sol#L357-L377)).
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
| `balanceOf(address)` | `0x70a08231` | ERC-20 |
| `transfer(address,uint256)` | `0xa9059cbb` | ERC-20 |
| `decimals()` | `0x313ce567` | ERC-20, Chainlink |
| `latestRoundData()` | `0xfeaf968c` | Chainlink |

## Refreshing

The Voter, VotingEscrow and bribe beacon are upgradeable. If Hydrex upgrades one, `test/Fork.t.sol` still passes at
its pinned block, so check the new implementation by hand: vendor its files, run `script/check-signatures.sh` and
the fork test at a newer block, and re-check the facts above. A changed fact may need a new deployment.
