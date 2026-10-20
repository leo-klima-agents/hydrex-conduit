// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

library Reference {
    function mulDiv(uint256 a, uint256 b, uint256 d) internal pure returns (uint256 q) {
        uint256 lo;
        uint256 hi;
        assembly ("memory-safe") {
            let mm := mulmod(a, b, not(0))
            lo := mul(a, b)
            hi := sub(sub(mm, lo), lt(mm, lo))
        }
        require(d > hi, "mulDiv overflow");
        if (hi == 0) return lo / d;
        uint256 r;
        for (uint256 i = 512; i > 0; --i) {
            uint256 bit = i > 256 ? (hi >> (i - 257)) & 1 : (lo >> (i - 1)) & 1;
            bool carry = r >> 255 == 1;
            r = (r << 1) | bit;
            if (carry || r >= d) {
                unchecked {
                    r -= d;
                }
                require(i <= 256, "quotient overflow");
                q |= 1 << (i - 1);
            }
        }
    }

    function share(uint256 b, uint256 v, uint256 x) internal pure returns (uint256) {
        return mulDiv(b, x, v + x);
    }

    function votesFor(uint256 weight, uint256 power, uint256 total) internal pure returns (uint256) {
        return weight * power / total;
    }

    function ratio(uint256 x) internal pure returns (uint256 r) {
        uint256 q = 1 << 128;
        uint256 b = q * 10_000 / 10_001;
        r = q;
        for (; x != 0; x >>= 1) {
            if (x & 1 == 1) r = mulDiv(r, b, q);
            b = mulDiv(b, b, q);
        }
    }

    function tailValue(int256 tick, uint256 amount, uint256 perUnit, uint256 div, uint256 cap)
        internal
        pure
        returns (uint256)
    {
        uint256 r = ratio(tick < 0 ? uint256(-tick) : uint256(tick));
        uint256 core = tick <= 0 ? mulDiv(amount, r, 1 << 128) : mulDiv(amount, 1 << 128, r);
        if (core > type(uint256).max / perUnit) return cap;
        uint256 usd = core * perUnit / div;
        return usd < cap ? usd : cap;
    }
}
