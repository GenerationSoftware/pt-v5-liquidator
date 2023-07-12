// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ILiquidationSource } from "./interfaces/ILiquidationSource.sol";
import { LiquidatorLib } from "./libraries/LiquidatorLib.sol";
import { SD59x18, convert, MAX_SD59x18 } from "prb-math/SD59x18.sol";

import { console2 } from "forge-std/console2.sol";

/**
 * @title PoolTogether Liquidation Pair
 * @author PoolTogether Inc. Team
 * @notice The LiquidationPair is a UniswapV2-like pair that allows the liquidation of tokens
 *          from an ILiquidationSource. Users can swap tokens in exchange for the tokens available.
 *          The LiquidationPair implements a virtual reserve system that results in the value
 *          tokens available from the ILiquidationSource to decay over time relative to the value
 *          of the token swapped in.
 * @dev Each swap consists of four steps:
 *       1. A virtual buyback of the tokens available from the ILiquidationSource. This ensures
 *          that the value of the tokens available from the ILiquidationSource decays as
 *          tokens accrue.
 *      2. The main swap of tokens the user requested.
 *      3. A virtual swap that is a small multiplier applied to the users swap. This is to
 *          push the value of the tokens being swapped back up towards the market value.
 *      4. A scaling of the virtual reserves. This is to ensure that the virtual reserves
 *          are large enough such that the next swap will have a realistic impact on the virtual
 *          reserves.
 */
contract LiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source;
  address public immutable tokenIn;
  address public immutable tokenOut;
  SD59x18 public targetExchangeRate; // tokenIn/tokenOut.
  SD59x18 public discoveryDeltaPercent; // % of time to use discovery curve
  // TODO: Adjust math st discoveryRate is a percentage to explore for the duration of phase 2. Make it a function of targetExchangeRate.
  SD59x18 public discoveryRate; // Rate to increase the discovery curve exchange rate by each second
  SD59x18 public exchangeRateSmoothing = convert(5); // Smooths the curve when the exchange rate is in phase 1 or phase 3.

  SD59x18 public immutable phaseOneEndPercent;
  SD59x18 public immutable phaseTwoEndPercent;

  /// @notice Sets the period of liquidations.
  uint32 public immutable periodLength;

  /// @notice Sets the beginning timestamp for the first period.
  /// @dev Ensure that the periodOffset is in the past.
  uint32 public immutable periodOffset;

  /* ============ Events ============ */

  /**
   * @notice Emitted when the pair is swapped.
   * @param account The account that swapped.
   * @param amountIn The amount of token in swapped.
   * @param amountOut The amount of token out swapped.
   * @param virtualReserveIn The updated virtual reserve of the token in.
   * @param virtualReserveOut The updated virtual reserve of the token out.
   */
  event Swapped(
    address indexed account,
    uint256 amountIn,
    uint256 amountOut,
    uint128 virtualReserveIn,
    uint128 virtualReserveOut
  );

  /* ============ Constructor ============ */

  constructor(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    SD59x18 _initialTargetExchangeRate,
    SD59x18 _discoveryDeltaPercent,
    SD59x18 _discoveryRate,
    uint32 _periodLength,
    uint32 _periodOffset
  ) {
    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
    targetExchangeRate = _initialTargetExchangeRate;
    discoveryDeltaPercent = _discoveryDeltaPercent;
    discoveryRate = _discoveryRate;
    periodLength = _periodLength;
    periodOffset = _periodOffset;

    phaseOneEndPercent = convert(50).sub(discoveryDeltaPercent);
    phaseTwoEndPercent = convert(50).add(discoveryDeltaPercent);
  }

  /* ============ External Methods ============ */
  /* ============ Read Methods ============ */

  /**
   * @notice Get the address that will receive `tokenIn`.
   * @return Address of the target
   */
  function target() external view returns (address) {
    return source.targetOf(tokenIn);
  }

  /**
   * @notice Computes the maximum amount of tokens that can be swapped in given the current state of the liquidation pair.
   * @return The maximum amount of tokens that can be swapped in.
   */
  function maxAmountIn() external view returns (uint256) {}

  /**
   * @notice Gets the maximum amount of tokens that can be swapped out from the source.
   * @return The maximum amount of tokens that can be swapped out.
   */
  function maxAmountOut() external view returns (uint256) {
    return _availableReserveOut();
  }

  function getTimeElapsed() external view returns (uint32) {
    return _getTimeElapsed();
  }

  function getPeriodStartTimestamp() external view returns (uint32) {
    return _getPeriodStartTimestamp(uint32(block.timestamp));
  }

  function getPeriodStartTimestamp(uint32 timestamp) external view returns (uint32) {
    return _getPeriodStartTimestamp(timestamp);
  }

  function getTimestampPeriod() external view returns (uint32) {
    return _getTimestampPeriod(uint32(block.timestamp));
  }

  function getTimestampPeriod(uint32 timestamp) external view returns (uint32) {
    return _getTimestampPeriod(timestamp);
  }

  // /**
  //  * @notice Computes the virtual reserves post virtual buyback of all available liquidity that has accrued.
  //  * @return The virtual reserve of the token in.
  //  * @return The virtual reserve of the token out.
  //  */
  // function nextLiquidationState() external view returns (uint128, uint128) {
  //   return
  //     LiquidatorLib._virtualBuyback(virtualReserveIn, virtualReserveOut, _availableReserveOut());
  // }

  // /**
  //  * @notice Computes the exact amount of tokens to receive out for the given amount of tokens to send in.
  //  * @param _amountIn The amount of tokens to send in.
  //  * @return The amount of tokens to receive out.
  //  */
  // function computeExactAmountOut(uint256 _amountIn) external view returns (uint256) {
  //   return
  //     LiquidatorLib.computeExactAmountOut(
  //       virtualReserveIn,
  //       virtualReserveOut,
  //       _availableReserveOut(),
  //       _amountIn
  //     );
  // }

  /* ============ External Methods ============ */

  function getAuctionState() external view returns (SD59x18 percentCompleted, uint8 phase) {
    return _getAuctionState();
  }

  function swapExactAmountOut(
    address _account,
    SD59x18 _amountOut,
    SD59x18 _amountInMax
  ) external returns (SD59x18) {
    (SD59x18 percentCompleted, uint8 phase) = _getAuctionState();

    SD59x18 exchangeRate = LiquidatorLib.getExchangeRate(
      phase,
      percentCompleted,
      exchangeRateSmoothing,
      discoveryRate,
      discoveryDeltaPercent,
      targetExchangeRate
    );
    SD59x18 amountIn = _computeAmountIn(_amountOut, exchangeRate);

    require(amountIn.lte(_amountInMax), "LiquidationPair/amount-in-exceeds-max");
    _updateTargetExchangeRate(exchangeRate);
    _swap(_account, _amountOut, amountIn);

    return amountIn;
  }

  function computeAmountIn(SD59x18 _amountOut) external returns (SD59x18) {
    (SD59x18 percentCompleted, uint8 phase) = _getAuctionState();

    console2.log("percentCompleted", convert(percentCompleted));
    console2.log("phase", phase);

    (bool success, bytes memory returnData) = address(this).delegatecall(
      abi.encodeWithSelector(
        this.getExchangeRate.selector,
        phase,
        percentCompleted,
        exchangeRateSmoothing,
        discoveryRate,
        discoveryDeltaPercent,
        targetExchangeRate
      )
    );

    SD59x18 exchangeRate;
    if (success) {
      exchangeRate = abi.decode(returnData, (SD59x18));
      // If exchange rate is negative, force to 0
      if (exchangeRate.lte(convert(0))) {
        return convert(0);
      }
    } else if (phase == 1) {
      return convert(0);
    } else if (phase == 3) {
      // NOTE: This might be too big.
      return MAX_SD59x18;
    }

    console2.log("exchangeRate", SD59x18.unwrap(exchangeRate));
    // NOTE: There's a chance of overflow/underflow within phase 2.
    // Need a smarter check for what value to return in that case.
    return _computeAmountIn(_amountOut, exchangeRate);
  }

  function computeAmountIn(
    SD59x18 _amountOut,
    SD59x18 exchangeRate
  ) external view returns (SD59x18) {
    return _computeAmountIn(_amountOut, exchangeRate);
  }

  function computeAmountOut(
    SD59x18 _amountIn,
    SD59x18 exchangeRate
  ) external view returns (SD59x18) {
    return _computeAmountOut(_amountIn, exchangeRate);
  }

  function getExchangeRate(
    uint8 _phase,
    SD59x18 _percentCompleted,
    SD59x18 _exchangeRateSmoothing,
    SD59x18 _discoveryRate,
    SD59x18 _discoveryDeltaPercent,
    SD59x18 _targetExchangeRate
  ) public view returns (SD59x18 exchangeRate) {
    return
      LiquidatorLib.getExchangeRate(
        _phase,
        _percentCompleted,
        _exchangeRateSmoothing,
        _discoveryRate,
        discoveryDeltaPercent,
        _targetExchangeRate
      );
  }

  /* ============ Internal Functions ============ */

  function _updateTargetExchangeRate(SD59x18 _exchangeRate) internal {
    // NOTE: Need to update a separate variable, otherwise the curves will change mid auction.
    targetExchangeRate = targetExchangeRate.add(_exchangeRate).div(convert(2));
  }

  function _computeAmountIn(
    SD59x18 _amountOut,
    SD59x18 exchangeRate
  ) internal pure returns (SD59x18) {
    return _amountOut.mul(exchangeRate);
  }

  function _computeAmountOut(
    SD59x18 _amountIn,
    SD59x18 exchangeRate
  ) internal pure returns (SD59x18) {
    return _amountIn.div(exchangeRate);
  }

  /**
   * @notice Gets the available liquidity that has accrued that users can swap for.
   * @return The available liquidity that users can swap for.
   */
  function _availableReserveOut() internal view returns (uint256) {
    return source.liquidatableBalanceOf(tokenOut);
  }

  /**
   * @notice Sends the provided amounts of tokens to the address given.
   * @param _account The address to send the tokens to.
   * @param _amountOut The amount of tokens to receive out.
   * @param _amountIn The amount of tokens sent in.
   */
  function _swap(address _account, SD59x18 _amountOut, SD59x18 _amountIn) internal {
    source.liquidate(
      _account,
      tokenIn,
      uint256(convert(_amountIn)),
      tokenOut,
      uint256(convert(_amountOut))
    );
  }

  function _getAuctionState() internal view returns (SD59x18 percentCompleted, uint8 phase) {
    uint32 timeElapsed = _getTimeElapsed();

    percentCompleted = timeElapsed > 0
      ? convert(int(uint(timeElapsed))).div(convert(int(uint(periodLength)))).mul(convert(100))
      : convert(0);

    if (percentCompleted.lte(phaseOneEndPercent)) {
      phase = 1;
    } else if (percentCompleted.lte(phaseTwoEndPercent)) {
      phase = 2;
    } else {
      phase = 3;
    }
  }

  function _getTimeElapsed() internal view returns (uint32) {
    return
      uint32(block.timestamp) > periodOffset
        ? uint32(block.timestamp) - _getPeriodStartTimestamp(uint32(block.timestamp))
        : 0;
  }

  function _getPeriodStartTimestamp(uint32 _timestamp) private view returns (uint32 timestamp) {
    uint32 period = _getTimestampPeriod(_timestamp);
    return period > 0 ? periodOffset + ((period - 1) * periodLength) : 0;
  }

  function _getTimestampPeriod(uint32 _timestamp) private view returns (uint32 period) {
    if (_timestamp <= periodOffset) {
      return 0;
    }
    // Shrink by 1 to ensure periods end on a multiple of periodLength.
    // Increase by 1 to start periods at # 1.
    return ((_timestamp - periodOffset - 1) / periodLength) + 1;
  }
}
