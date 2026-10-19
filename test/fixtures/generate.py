#!/usr/bin/env python3
import functools
import json
import math
import os
import subprocess
import sys
import time
import urllib.request

RPC = os.environ["BASE_RPC_URL"]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fork.json")

VOTER = "0xc69E3eF39E3fFBcE2A1c570f8d3ADF76909ef17b"
VE = "0x25B2ED7149fb8A05f6eF9407d9c8F878f59cd1e1"
KLIMA_CONDUIT = "0xdE91885cF35ac57DF0c4A75c16862127dBe8317c"
TOKEN_ID = 14247
WEEK = 604800
MAX_POOLS = 20
GAS_POOLS = 40
USDC = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
WETH = "0x4200000000000000000000000000000000000006"
HYDX = "0x00000e7efa313F4E11Bfff432471eD9423AC6B30"
PRICED = [
    (WETH, "0x50015f8b17fb2C290Dde41fDc246ed0dcEE93a8b", 1, 10**8),
    ("0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf", "0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D", 100, 1),
    (USDC, "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B", 10**4, 1),
    ("0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42", "0xDAe398520e2B67cd3f27aeF9Cf14D93D927f8250", 10**4, 1),
]


def rpc(batch):
    out = []
    for i in range(0, len(batch), 40):
        chunk = [{"jsonrpc": "2.0", "id": j, "method": m, "params": p} for j, (m, p) in enumerate(batch[i : i + 40])]
        for attempt in range(5):
            time.sleep(1 + 2 * attempt)
            req = urllib.request.Request(RPC, json.dumps(chunk).encode(), {"content-type": "application/json"})
            res = sorted(json.load(urllib.request.urlopen(req)), key=lambda r: r["id"])
            if not any("limit" in r.get("error", {}).get("message", "") for r in res):
                break
        for r in res:
            if "error" in r:
                raise RuntimeError(r["error"])
            out.append(r["result"])
    return out


def word(x):
    return (x[2:].lower() if isinstance(x, str) else format(x, "x")).rjust(64, "0")


@functools.cache
def selector(signature):
    return subprocess.check_output(["cast", "sig", signature], text=True).strip()


def calls(block, items):
    tag = hex(block)
    res = rpc(
        [
            ("eth_call", [{"to": to, "data": selector(sig) + "".join(word(a) for a in args)}, tag])
            for to, sig, args in items
        ]
    )
    return [[int(r[2 + 64 * k : 2 + 64 * (k + 1)], 16) for k in range((len(r) - 2) // 64)] for r in res]


def addr(n):
    return "0x" + format(n, "040x")


def share(b, v, x):
    d = v + x
    return b // d * x + b % d * x // d


def waterfill(values, others, power):
    lo, hi = 0.0, max(b / v for b, v in zip(values, others))
    for _ in range(200):
        lam = (lo + hi) / 2
        total = sum(max(0.0, math.sqrt(b * v / lam) - v) for b, v in zip(values, others))
        lo, hi = (lam, hi) if total > power else (lo, lam)
    return [max(0.0, math.sqrt(b * v / hi) - v) for b, v in zip(values, others)]


def main():
    latest = int(rpc([("eth_blockNumber", [])])[0], 16)
    block = int(sys.argv[1]) if len(sys.argv) > 1 else latest - 2

    (klima_n,) = calls(block, [(VOTER, "poolVoteLength(address)", [KLIMA_CONDUIT])])[0]
    kpools = [
        addr(r[0])
        for r in calls(block, [(VOTER, "poolVote(address,uint256)", [KLIMA_CONDUIT, i]) for i in range(klima_n)])
    ]
    kg = [addr(r[0]) for r in calls(block, [(VOTER, "gauges(address)", [p]) for p in kpools])]
    kext = [addr(r[0]) for r in calls(block, [(VOTER, "external_bribes(address)", [g]) for g in kg])]
    kint = [addr(r[0]) for r in calls(block, [(VOTER, "internal_bribes(address)", [g]) for g in kg])]
    tokens = [USDC, WETH, HYDX]
    e = {
        t: [r[0] for r in calls(block, [(b, "earned(uint256,address)", [TOKEN_ID, t]) for b in kext + kint])]
        for t in tokens
    }
    claim = {
        "bribes": [b for i, b in enumerate(kext) if any(e[t][i] for t in tokens)],
        "fees": [b for i, b in enumerate(kint) if any(e[t][len(kext) + i] for t in tokens)],
        "tokens": tokens,
        "amounts": [str(sum(e[t])) for t in tokens],
    }

    (epoch,), (n,) = calls(block, [(VOTER, "_epochTimestamp()", []), (VOTER, "length()", [])])
    (power,) = calls(block, [(VE, "balanceOfNFTAt(uint256,uint256)", [TOKEN_ID, epoch + WEEK])])[0]
    answers = [r[1] for r in calls(block, [(f, "latestRoundData()", []) for _, f, _, _ in PRICED])]
    pools = [addr(r[0]) for r in calls(block, [(VOTER, "pools(uint256)", [i]) for i in range(n)])]
    gauges = [addr(r[0]) for r in calls(block, [(VOTER, "gauges(address)", [p]) for p in pools])]
    alive = [r[0] == 1 for r in calls(block, [(VOTER, "isAlive(address)", [g]) for g in gauges])]
    live = [(p, g) for p, g, a in zip(pools, gauges, alive) if a]
    ext = [addr(r[0]) for r in calls(block, [(VOTER, "external_bribes(address)", [g]) for _, g in live])]
    intl = [addr(r[0]) for r in calls(block, [(VOTER, "internal_bribes(address)", [g]) for _, g in live])]
    weights = [r[0] for r in calls(block, [(VOTER, "weights(address)", [p]) for p, _ in live])]
    usdc_ok = [r[0] == 1 for r in calls(block, [(b, "isRewardToken(address)", [USDC]) for b in ext])]

    items = [
        (k, b, t, mul, div, a)
        for k in range(len(live))
        for b in (ext[k], intl[k])
        for (t, _, mul, div), a in zip(PRICED, answers)
    ]
    amounts = [
        r[1] for r in calls(block, [(b, "rewardData(address,uint256)", [t, epoch]) for _, b, t, _, _, _ in items])
    ]
    values, deposits = [0] * len(live), [[] for _ in live]
    for (k, b, t, mul, div, a), x in zip(items, amounts):
        values[k] += x * a * mul // div
        if x:
            deposits[k].append((b, t, x))

    ranked = sorted(range(len(live)), key=lambda k: -values[k])
    candidates = [k for k in ranked if values[k] > 0 and weights[k] > 0][:60]
    chosen = candidates
    for _ in range(50):
        xs = waterfill([values[k] for k in chosen], [weights[k] for k in chosen], power)
        gains = sorted(((values[k] * x / (weights[k] + x), k) for k, x in zip(chosen, xs) if x >= 1), reverse=True)
        nxt = [k for _, k in gains[:MAX_POOLS]]
        if set(nxt) == set(chosen):
            break
        chosen = nxt
    xs = waterfill([values[k] for k in chosen], [weights[k] for k in chosen], power)
    assert len(chosen) <= MAX_POOLS and all(x >= 1 for x in xs)
    optimum = sum(values[k] * x / (weights[k] + x) for k, x in zip(chosen, xs))
    ws = [int(x) for x in xs]
    total = sum(ws)
    score = sum(share(values[k], weights[k], w * power // total) for k, w in zip(chosen, ws))

    gas = [k for k in range(len(live)) if usdc_ok[k]][:GAS_POOLS]
    assert len(gas) == GAS_POOLS

    fixture = {
        "block": block,
        "epoch": epoch,
        "power": str(power),
        "answers": [str(a) for a in answers],
        "market": {
            "pools": [live[k][0] for k in chosen],
            "weights": [str(w) for w in ws],
            "values": [str(values[k]) for k in chosen],
            "others": [str(weights[k]) for k in chosen],
            "score": str(score),
            "optimum": str(int(optimum)),
            "bribes": [d[0] for k in chosen for d in deposits[k]],
            "tokens": [d[1] for k in chosen for d in deposits[k]],
            "amounts": [str(d[2]) for k in chosen for d in deposits[k]],
        },
        "gasPools": [live[k][0] for k in gas],
        "claim": claim,
    }
    with open(OUT, "w") as f:
        json.dump(fixture, f, indent=2)
        f.write("\n")
    print(f"wrote {OUT} at block {block}: {len(chosen)} pools, score {score / 1e18:.2f} USD")


if __name__ == "__main__":
    main()
