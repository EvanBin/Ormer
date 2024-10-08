// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0 <0.9.0;

import './ABDKMath64x64.sol';

// Q-Number Math on Q64.96
// https://en.wikipedia.org/wiki/Q_(number_format)
library PriceMath {

    uint8 internal constant CLIP = 32;

    function add(int128 x, int128 y) internal pure returns (int128 z) {
        z = ABDKMath64x64.add(x, y);
    }

    function sub(int128 x, int128 y) internal pure returns (int128 z) {
        z = ABDKMath64x64.sub(x, y);
    }

    function mul(int128 x, int128 y) internal pure returns (int128 z) {
        z = ABDKMath64x64.mul(x, y);
    }

    function div(int128 x, int128 y) internal pure returns (int128 z) {
        z = ABDKMath64x64.div(x, y);
    }

    function toQ64x64(uint160 y) internal pure returns (int128 z) {
        require((z = int128(int160(y>>CLIP))) == int160(y>>CLIP));
    }

    function uint16toQ64x64(uint16 y) internal pure returns (int128 z) {
        z = int128(uint128(y) << 64);
    }

    function toQ64x96(int128 y) internal pure returns (uint160 z) {
        z = uint160(int160(y<<CLIP));
    }

    function sqrtPrice2Price(int128 y) internal pure returns (int128 z) {
        z = ABDKMath64x64.pow(y, 2);
    }

    function price2SqrtPrice(int128 y) internal pure returns (int128 z) {
        z = ABDKMath64x64.sqrt(y);
    }
}