// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0 <0.9.0;

import './libraries/TickMath.sol';
import './libraries/PriceMath.sol';

contract Ormer {
    using PriceMath for int128;

    // Streaming Storage
    struct Slot {
        int24[5] marker_heights; // 5*24 = 120
        int24 estimation_last;

        uint16[5] marker_pos; // 5*16 = 80
        uint16 obs_count;
        uint16 window_size;
    }

    Slot public ormer_full;
    Slot public ormer_half;

    // Config
    address private ormer_creator;

    // Constants
    int128 private constant K64X64_0_5 = 0x8000000000000000;
    int128 private constant K64X64_1_0 = 0x10000000000000000;
    int128 private constant K64X64_N_1_0 = -1 << 64;

    int128 private constant INC1 = 0x4000000000000000;
    int128 private constant INC2 = 0x8000000000000000;
    int128 private constant INC3 = 0xc000000000000000;
    int128 private constant INC4 = 0x10000000000000000;

    // <=========================== Test Functions ===========================>
    // |                                                                      |
    // |                                                                      |
    function testRound(bool round) external pure returns (uint24 z) {
        int128 a = 1 << 64;
        if (round) {
            a = a + (1 << 63);
        }
        z = _round64x64(a);
    }

    function testPrice() external pure returns (int128 z) {
        z = _getPrice(202919);
    }

    function testSort(int24[5] memory inputArray) external pure returns (int24[5] memory) {
        return _sort5(inputArray);
    }
    // |                                                                      |
    // |                                                                      |
    // <======================================================================>


    // <======================= Contract Configuration =======================>
    // |                                                                      |
    // |                                                                      |
    constructor() {
        ormer_creator = msg.sender;
    }

    function _changeWindowSize(uint16 new_window_size) internal {
        // Ormer Half need at least 5 markers
        require(new_window_size > 9, "Window size should be bigger than 9");
        ormer_full.window_size = new_window_size;
        ormer_half.window_size = new_window_size >> 1;
    }

    function changeWindowSize(uint16 new_window_size) external {
        _changeWindowSize(new_window_size);
    }

    function initialize(uint16 window_size) external {
        require(msg.sender == ormer_creator, "Only the creator can invoke initialize()");
        // Initial window size
        _changeWindowSize(window_size);
        // Reset Slots in Initializing Mode
        _reset(true, true);
        _reset(true, false);
    }
    // |                                                                      |
    // |                                                                      |
    // <======================================================================>
    

    // <=========================== Ormer Interface ==========================>
    // |                                                                      |
    // |                                                                      |
    // Return current price, not sqrtPrice
    // event logMiddle(int128 term1, int128 term2);
    // event logPrice(int128, int128);
    function _getMedian(Slot memory ormer_slot) internal pure returns (int128 current_price) {
        int128 obs_fraction = PriceMath.uint16toQ64x64(ormer_slot.obs_count).div(
                                PriceMath.uint16toQ64x64(ormer_slot.window_size));
        
        current_price = (K64X64_1_0.sub(obs_fraction)).mul((_getPrice(ormer_slot.estimation_last))).add(
            obs_fraction.mul((_getPrice(_ormerMedian(ormer_slot))))
        );

        // emit logPrice((K64X64_1_0.sub(obs_fraction)).mul((_getPrice(ormer_slot.estimation_last))), obs_fraction.mul((_getPrice(_ormerMedian(ormer_slot)))));
        // emit logMiddle((K64X64_1_0.sub(obs_fraction)).mul(_getPrice(ormer_slot.estimation_last)), obs_fraction.mul((_getPrice(_ormerMedian(ormer_slot)))));
    }

    function getMedian() external view returns (int128 current_price) {
        int128 current_price_full = _getMedian(ormer_full);
        int128 current_price_half = _getMedian(ormer_half);

        int128 rotation_factor = K64X64_0_5.add(
            K64X64_0_5.mul(
                (current_price_half.div(current_price_full)).sub(K64X64_1_0)
            )
        );

        current_price = current_price_half.add(rotation_factor.mul(current_price_half.sub(current_price_full)));
    }

    function update(int24 spotTick) external {
        // Full Window Update
        _ormerUpdate(true, spotTick);
        // Half Window Update
        _ormerUpdate(false, spotTick);
    }
    // |                                                                      |
    // |                                                                      |
    // <======================================================================>


    // <============================ Ormer Median ============================>
    // |                                                                      |
    // |                                                                      |
    function _ormerUpdate(bool slot_select, int24 spotTick) internal {
        Slot storage ormer_slot;

        if (slot_select) {
            ormer_slot = ormer_full;
        }
        else {
            ormer_slot = ormer_half;
        }

        ormer_slot.obs_count = ormer_slot.obs_count + 1;

        require(ormer_slot.obs_count > 0, "Observation Count Error");
        require(ormer_slot.window_size > 4, "Window Size Not Initialized");

        // Reach window size
        if (ormer_slot.obs_count == ormer_slot.window_size) {
            // Update Last Estimation
            ormer_slot.estimation_last = _ormerMedian(ormer_slot);

            // Reset Slots in Sliding Mode
            _reset(false, slot_select);
        }

        // Not initiated, 5 markers to initiate
        if (ormer_slot.obs_count < 6) {

            // Fill not initiated marker heights
            ormer_slot.marker_heights[uint24(ormer_slot.obs_count - 1)] = spotTick;

            // Check if should be Initiated
            if (ormer_slot.obs_count == 5) {
                ormer_slot.marker_heights = _sort5(ormer_slot.marker_heights);
            }
            else {
                return;
            }
        }

        // Find the higher marker whose height is lower than observation
        uint8 marker_index = 0;
        if (spotTick < ormer_slot.marker_heights[0]) {
            ormer_slot.marker_heights[0] = spotTick;
        }
        else {
            while (((marker_index+1) < 5) && (spotTick >= ormer_slot.marker_heights[marker_index+1])) {
                marker_index = marker_index + 1;
            }

            // Last Marker
            if (marker_index == 4) {
                ormer_slot.marker_heights[4] = spotTick;
                marker_index = 3;
            }
        }

        // Adjust Marker Position
        marker_index = marker_index + 1;
        for(; marker_index < 5; marker_index++) {
            ormer_slot.marker_pos[marker_index] = ormer_slot.marker_pos[marker_index] + 1;
        }

        // Estimate Desired Marker Positions
        int128[5] memory marker_desired;
        int128 obs_count_Q64x64 = PriceMath.uint16toQ64x64(ormer_slot.obs_count);

        marker_desired[0] = 0;
        marker_desired[1] = INC1.mul(obs_count_Q64x64);
        marker_desired[2] = INC2.mul(obs_count_Q64x64);
        marker_desired[3] = INC3.mul(obs_count_Q64x64);
        marker_desired[4] = INC4.mul(obs_count_Q64x64);

        // Adjust Marker Height Values
        int128 distance;
        int8 d_index;
        int128 hprime;
        int128[3] memory marker_pos_tmp;
        // Convert from tick to price
        int128[5] memory marker_heights;
        marker_heights[0] = _getPrice(ormer_slot.marker_heights[0]);
        marker_heights[1] = _getPrice(ormer_slot.marker_heights[1]);
        marker_heights[2] = _getPrice(ormer_slot.marker_heights[2]);
        marker_heights[3] = _getPrice(ormer_slot.marker_heights[3]);
        marker_heights[4] = _getPrice(ormer_slot.marker_heights[4]);

        for (uint8 i=1;i<4;i++) {

            // Convert to computable Q64x64
            marker_pos_tmp[0] = PriceMath.uint16toQ64x64(ormer_slot.marker_pos[i-1]);
            marker_pos_tmp[1] = PriceMath.uint16toQ64x64(ormer_slot.marker_pos[i]);
            marker_pos_tmp[2] = PriceMath.uint16toQ64x64(ormer_slot.marker_pos[i+1]);

            // Distance calculation
            distance = marker_desired[i].sub(marker_pos_tmp[1]);

            if (((distance >= K64X64_1_0) && ((marker_pos_tmp[2]).sub(marker_pos_tmp[1]) > K64X64_1_0)) ||
                ((distance <= K64X64_N_1_0) && ((marker_pos_tmp[0]).sub(marker_pos_tmp[1]) < K64X64_N_1_0))) {
                    // Rounding to integer
                    if (distance < 0) {
                        distance = K64X64_N_1_0;
                        d_index = -1;
                    }
                    else {
                        distance = K64X64_1_0;
                        d_index = 1;
                    }

                    // Try Parabolic formula
                    hprime = (
                        marker_heights[i].add(
                            // Term 1
                            (distance.div(marker_pos_tmp[2].sub(marker_pos_tmp[0]))).mul(
                                // Term 2
                                (((marker_pos_tmp[1].sub(marker_pos_tmp[0]).add(distance)).mul(
                                    marker_heights[i+1].sub(marker_heights[i])
                                )).div(
                                    marker_pos_tmp[2].sub(marker_pos_tmp[1])
                                )).add(
                                    // Term 3
                                    ((marker_pos_tmp[2].sub(marker_pos_tmp[1]).sub(distance)).mul(
                                        marker_heights[i].sub(marker_heights[i-1])
                                    )).div(
                                        marker_pos_tmp[1].sub(marker_pos_tmp[0])
                                    )
                                )
                            )
                        )
                    );
                    
                    if ((marker_heights[i-1] < hprime) && (hprime < marker_heights[i+1])) {
                        marker_heights[i] = hprime;
                    }
                    else {
                        // Linear formula
                        hprime = (
                            marker_heights[i].add(
                                // Term 1
                                (distance.mul(
                                    marker_heights[uint8(int8(i)+d_index)].sub(marker_heights[i])
                                )).div(
                                    // Term 2
                                    PriceMath.uint16toQ64x64(
                                        ormer_slot.marker_pos[uint8(int8(i)+d_index)]
                                    ).sub(marker_pos_tmp[1])
                                )
                            )
                        );
                        marker_heights[i] = hprime;
                    }
            }
        }

        // Convert from price to tick
        ormer_slot.marker_heights[0] = _price2Tick(marker_heights[0]);
        ormer_slot.marker_heights[1] = _price2Tick(marker_heights[1]);
        ormer_slot.marker_heights[2] = _price2Tick(marker_heights[2]);
        ormer_slot.marker_heights[3] = _price2Tick(marker_heights[3]);
        ormer_slot.marker_heights[4] = _price2Tick(marker_heights[4]);
    }

    // event logMedianCal(uint24);
    function _ormerMedian(Slot memory ormer_slot) internal pure returns (int24) {
        if (ormer_slot.obs_count > 2) {
            return ormer_slot.marker_heights[2];
        }
        else {
            // emit logMedianCal(_round64x64(K64X64_0_5.mul(PriceMath.uint16toQ64x64(ormer_slot.obs_count-1))));
            return ormer_slot.marker_heights[_round64x64(K64X64_0_5.mul(PriceMath.uint16toQ64x64(ormer_slot.obs_count-1)))];
        }
    }
    // |                                                                      |
    // |                                                                      |
    // <======================================================================>


    // <======================== Price Math Functions ========================>
    // |                                                                      |
    // |                                                                      |
    function _getSqrtPrice(int24 tick) internal pure returns (int128 z) {
        z = PriceMath.toQ64x64(TickMath.getSqrtRatioAtTick(tick));
    }

    function _getPrice(int24 tick) internal pure returns (int128 z) {
        z = _getSqrtPrice(tick).sqrtPrice2Price();
    }

    function _price2Tick(int128 price) internal pure returns (int24 z) {
        z = TickMath.getTickAtSqrtRatio(price.price2SqrtPrice().toQ64x96());
    }

    function _round64x64(int128 y) internal pure returns (uint24 z) {

        require(y < 0x10000000000000000000000);

        if ((y & K64X64_0_5) == K64X64_0_5) {
            z = uint24(int24(y >> 64) + 1);
        }
        else {
            z = uint24(int24(y >> 64));
        }
    }
    // |                                                                      |
    // |                                                                      |
    // <======================================================================>


    // <========================== Slot Management ===========================>
    // |                                                                      |
    // |                                                                      |
    function _reset(bool initial, bool slot_select) private {
        if (initial) {
            ormer_full.estimation_last = 0;
            ormer_full.obs_count = 0;
            ormer_half.estimation_last = 0;
            ormer_half.obs_count = 0;

            ormer_full.marker_heights[0] = 0;
            ormer_full.marker_heights[1] = 0;
            ormer_full.marker_heights[2] = 0;
            ormer_full.marker_heights[3] = 0;
            ormer_full.marker_heights[4] = 0;

            // Avoid writing all zero to one slot
            ormer_full.marker_pos[0] = 1;
            ormer_full.marker_pos[1] = 2;
            ormer_full.marker_pos[2] = 3;
            ormer_full.marker_pos[3] = 4;
            ormer_full.marker_pos[4] = 5;

            ormer_half.marker_heights[0] = 0;
            ormer_half.marker_heights[1] = 0;
            ormer_half.marker_heights[2] = 0;
            ormer_half.marker_heights[3] = 0;
            ormer_half.marker_heights[4] = 0;

            // Avoid writing all zero to one slot
            ormer_half.marker_pos[0] = 1;
            ormer_half.marker_pos[1] = 2;
            ormer_half.marker_pos[2] = 3;
            ormer_half.marker_pos[3] = 4;
            ormer_half.marker_pos[4] = 5;
        }
        else {
            if (slot_select) {
                ormer_full.obs_count = 1;

                ormer_full.marker_heights[0] = 0;
                ormer_full.marker_heights[1] = 0;
                ormer_full.marker_heights[2] = 0;
                ormer_full.marker_heights[3] = 0;
                ormer_full.marker_heights[4] = 0;

                // Avoid writing all zero to one slot
                ormer_full.marker_pos[0] = 1;
                ormer_full.marker_pos[1] = 2;
                ormer_full.marker_pos[2] = 3;
                ormer_full.marker_pos[3] = 4;
                ormer_full.marker_pos[4] = 5;
            }
            else {
                ormer_half.obs_count = 1;

                ormer_half.marker_heights[0] = 0;
                ormer_half.marker_heights[1] = 0;
                ormer_half.marker_heights[2] = 0;
                ormer_half.marker_heights[3] = 0;
                ormer_half.marker_heights[4] = 0;

                // Avoid writing all zero to one slot
                ormer_half.marker_pos[0] = 1;
                ormer_half.marker_pos[1] = 2;
                ormer_half.marker_pos[2] = 3;
                ormer_half.marker_pos[3] = 4;
                ormer_half.marker_pos[4] = 5;
            }
        }
    }
    // |                                                                      |
    // |                                                                      |
    // <======================================================================>


    // <============================= Utilities ==============================>
    // |                                                                      |
    // |                                                                      |
    function _sort5(int24[5] memory array) internal pure returns (int24[5] memory) {

        bool swapped;

        for (uint8 i = 0; i < 4; i++) {
            swapped = false;
            for (uint8 j = 0; j < 4 - i; j++) {
                if (array[j] > array[j + 1]) {
                    (array[j], array[j + 1]) = (array[j + 1], array[j]);
                    swapped = true;
                }
            }
            if (!swapped) break; // If no swaps occurred, the array is already sorted
        }

        return array;
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // truncation is desired
    }
    // |                                                                      |
    // |                                                                      |
    // <======================================================================>
}