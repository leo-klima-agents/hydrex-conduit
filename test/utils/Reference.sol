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
}
