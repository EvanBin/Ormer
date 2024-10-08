# Ormer

This repository illustrates the smart contract implementation of $\textbf{Ormer}$ algorithm with EVM compatible `Solidity` language.

## Usage

After contract deployment, invoke `Ormer.initialize` to set window size. The range of window size is limited to $[10, 65535]$ in this implementation.

```solidity
function initialize(uint16 window_size)
```

Invoke `Ormer.update` with the tick of spot price for `Ormer` estimation update.

```solidity
function update(int24 spotTick)
```

When at least one spot price is updated to `Ormer`, you may invoke `Ormer.getMedian` for oracle price query.

```solidity
function getMedian() external view returns (int128 current_price)
```

The returned current oracle price is a `int128` fixed point number with $2^{64}$ denominator (Q64.64). 

## License

The license for $\textbf{Ormer}$ Contract implementation is `GPL-3.0`.
