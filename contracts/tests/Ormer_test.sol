// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0 <0.9.0;

import "../libraries/TickMath.sol";
import "../libraries/PriceMath.sol";

contract Ormer_test {
    function testToQ64x64() external pure returns (uint160 sqrtPriceX96, uint160 priceAfter, int24 tick) {
        tick = 202919;
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        priceAfter = uint160(int160(PriceMath.toQ64x64(sqrtPriceX96)<<32));
        return (sqrtPriceX96, priceAfter, TickMath.getTickAtSqrtRatio(priceAfter));
    }

    function testX96Math() external pure returns (uint160 plus, uint160 sub, uint160 mul, uint160 div, int128 subBase, int128 subTest)  {
        int24 tick = 202919;
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

        int128 a = PriceMath.toQ64x64(sqrtPriceX96);
        a = PriceMath.sqrtPrice2Price(a);

        tick = 203000;
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

        int128 b = PriceMath.toQ64x64(sqrtPriceX96);
        b = PriceMath.sqrtPrice2Price(b);

        plus = PriceMath.toQ64x96(PriceMath.price2SqrtPrice(PriceMath.add(a, b)));
        sub = PriceMath.toQ64x96(PriceMath.price2SqrtPrice(PriceMath.sub(b, a)));
        mul = PriceMath.toQ64x96(PriceMath.price2SqrtPrice(PriceMath.mul(a, b)));
        div = PriceMath.toQ64x96(PriceMath.price2SqrtPrice(PriceMath.div(a, b)));

        subBase = -1 << 64;
        subTest = PriceMath.sub(0x10000000000000000, 0x20000000000000000);
    }

    function testNegative() external pure returns (bool a, bool b) {
        a = PriceMath.sub(0x10000000000000000, 0x30000000000000000) > int(-1 << 64);
        b = PriceMath.sub(0x10000000000000000, 0x30000000000000000) < int(-1 << 64);
    }

    function testNegative2() external pure returns (int128 a) {
        a = PriceMath.sub(0x10000000000000000, 0x30000000000000000);
        a = PriceMath.add(a, 0x40000000000000000);
    }

    function testGetPrice() external pure returns (int128 z) {
        z = PriceMath.toQ64x64(TickMath.getSqrtRatioAtTick(202919));
        z = PriceMath.sqrtPrice2Price(z);
    }

    int128 constant ROUNDCHECK = 0x8000000000000000;

    function testRound(bool expected) external pure returns (bool) {
        int128 a = 1 << 64;
        
        if (expected) {
            a = a + (1 << 63);
        }

        return (a & ROUNDCHECK) == ROUNDCHECK;
    }

    function testTickMath() external pure returns (uint160 sqrtPriceX96, int24 tick) {
        sqrtPriceX96 = 2018382873588440326581633304624437;
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        return (TickMath.getSqrtRatioAtTick(tick), tick);
    }
}