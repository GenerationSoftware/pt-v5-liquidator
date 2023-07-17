// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";
import { ILiquidationPair } from "v5-liquidator-interfaces/ILiquidationPair.sol";

import { LiquidatorLib } from "./libraries/LiquidatorLib.sol";
import { SD59x18, convert, MAX_SD59x18 } from "prb-math/SD59x18.sol";

/**
 * @title PoolTogether Liquidation Pair
 * @author PoolTogether Inc. Team
 * @notice The LiquidationPair sells tokens on through Dutch Auctions over the course of defined a period of time. The exchange rate traverses from infinity to zero every period, hitting a target exchange rate in the middle of the period and allowing for controlled price exploration surrounding the target exchange rate.
 */
contract LiquidationPair is ILiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source;
  address public immutable tokenIn;
  address public immutable tokenOut;
  SD59x18 public targetExchangeRate; // tokenIn/tokenOut.
  SD59x18 public nextTargetExchangeRate; // tokenIn/tokenOut.
  SD59x18 public maxAmountOutThisPeriod; // The maximum amount of tokenOut that can be liquidated for period N. The total amount accured during period N-1.
  SD59x18 public phaseTwoDurationPercent; // % of time to traverse during phase 2.
  SD59x18 public phaseTwoRangePercent; // % of target exchange rate to traverse during phase 2.
  SD59x18 public exchangeRateSmoothing = convert(5); // Smooths the curve when the exchange rate is in phase 1 or phase 3.

  uint32 public currentPeriod; // The current period that the state reflects.

  SD59x18 public immutable phaseTwoDurationPercentHalved;
  SD59x18 public immutable phaseTwoRangePercentHalved;
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

  /* ============ Modifiers ============ */

  /**
   * @notice Updates the period state if the period has changed.
   * @dev This modifier is used to update the period state before a function that relies on the state is executed.
   */
  modifier updatePeriodState() {
    uint32 currentPeriod_ = _getTimestampPeriod(uint32(block.timestamp));

    if (currentPeriod_ != currentPeriod) {
      currentPeriod = currentPeriod_;
      maxAmountOutThisPeriod = convert(int(_availableReserveOut()));
      targetExchangeRate = nextTargetExchangeRate;
    }
    _;
  }

  /* ============ Constructor ============ */

  constructor(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    SD59x18 _initialTargetExchangeRate,
    SD59x18 _phaseTwoDurationPercent,
    SD59x18 _phaseTwoRangePercent,
    uint32 _periodLength,
    uint32 _periodOffset
  ) {
    // NOTE: Could probably allow 0 so there's no phase 2. Needs more testing.
    require(_phaseTwoDurationPercent.gt(convert(0)), "LiquidationPair/invalid-phase-two-duration");
    require(
      _phaseTwoDurationPercent.lt(convert(100)),
      "LiquidationPair/invalid-phase-two-duration"
    );
    require(_phaseTwoRangePercent.lt(convert(100)), "LiquidationPair/invalid-phase-two-range");
    // NOTE: phaseTwoRangePercent of 0 means for the duration of phase 2, the exchange rate will be the target exchange rate.
    require(_phaseTwoRangePercent.gte(convert(0)), "LiquidationPair/invalid-phase-two-range");

    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
    targetExchangeRate = _initialTargetExchangeRate;
    nextTargetExchangeRate = _initialTargetExchangeRate;
    phaseTwoDurationPercent = _phaseTwoDurationPercent;
    phaseTwoRangePercent = _phaseTwoRangePercent;
    periodLength = _periodLength;
    periodOffset = _periodOffset;

    phaseTwoDurationPercentHalved = phaseTwoDurationPercent.div(convert(2));
    phaseTwoRangePercentHalved = phaseTwoRangePercent.div(convert(2));
    phaseOneEndPercent = convert(50).sub(phaseTwoDurationPercentHalved);
    phaseTwoEndPercent = convert(50).add(phaseTwoDurationPercentHalved);
  }

  /* ============ External Methods ============ */
  /* ============ Read Methods ============ */

  /// @inheritdoc ILiquidationPair
  function target() external view returns (address) {
    return source.targetOf(tokenIn);
  }

  /// @inheritdoc ILiquidationPair
  function maxAmountIn() external updatePeriodState returns (uint256) {
    (SD59x18 amountIn, ) = _computeExactAmountIn(maxAmountOutThisPeriod);
    return uint(convert(amountIn));
  }

  /// @inheritdoc ILiquidationPair
  function maxAmountOut() external updatePeriodState returns (uint256) {
    return uint(convert(maxAmountOutThisPeriod));
  }

  /**
   * @notice Gets the time elapsed since the start of the current period.
   * @return The time elapsed since the start of the current period.
   */
  function getTimeElapsed() external view returns (uint32) {
    return _getTimeElapsed();
  }

  /**
   * @notice Gets the starting timestamp of the current period.
   * @return The starting timestamp of the current period.
   */
  function getPeriodStartTimestamp() external view returns (uint32) {
    return _getPeriodStartTimestamp(uint32(block.timestamp));
  }

  /**
   * @notice Gets the starting timestamp of the period that the timestamp falls in.
   * @param timestamp The timestamp to get the period start for.
   * @return The starting timestamp of the period that the timestamp falls in.
   */
  function getPeriodStartTimestamp(uint32 timestamp) external view returns (uint32) {
    return _getPeriodStartTimestamp(timestamp);
  }

  /**
   * @notice Gets the period that the current timestamp falls in.
   * @return The period that the current timestamp falls in.
   */
  function getTimestampPeriod() external view returns (uint32) {
    return _getTimestampPeriod(uint32(block.timestamp));
  }

  /**
   * @notice Gets the period that the timestamp falls in.
   * @param timestamp The timestamp to get the period for.
   * @return The period that the timestamp falls in.
   */
  function getTimestampPeriod(uint32 timestamp) external view returns (uint32) {
    return _getTimestampPeriod(timestamp);
  }

  /* ============ External Methods ============ */

  /**
   * @notice Gets the current state of the auction.
   * @return percentCompleted The percent completed of the auction.
   * @return phase The current phase of the auction.
   */
  function getAuctionState() external view returns (SD59x18 percentCompleted, uint8 phase) {
    return _getAuctionState();
  }

  /// @inheritdoc ILiquidationPair
  function swapExactAmountIn(
    address _receiver,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) external updatePeriodState returns (uint256) {
    return
      uint(
        convert(_swapExactAmountIn(_receiver, convert(int(_amountIn)), convert(int(_amountOutMin))))
      );
  }

  function swapExactAmountIn(
    address _account,
    SD59x18 _amountIn,
    SD59x18 _amountOutMin
  ) external updatePeriodState returns (SD59x18) {
    return _swapExactAmountIn(_account, _amountIn, _amountOutMin);
  }

  /// @inheritdoc ILiquidationPair
  function swapExactAmountOut(
    address _receiver,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external updatePeriodState returns (uint256) {
    return
      uint(
        convert(
          _swapExactAmountOut(_receiver, convert(int(_amountOut)), convert(int(_amountInMax)))
        )
      );
  }

  function swapExactAmountOut(
    address _account,
    SD59x18 _amountOut,
    SD59x18 _amountInMax
  ) external updatePeriodState returns (SD59x18) {
    return _swapExactAmountOut(_account, _amountOut, _amountInMax);
  }

  /// @inheritdoc ILiquidationPair
  function computeExactAmountIn(uint256 _amountOut) external updatePeriodState returns (uint256) {
    (SD59x18 amountIn, ) = _computeExactAmountIn(convert(int256(_amountOut)));
    return uint256(convert(amountIn));
  }

  function computeExactAmountIn(SD59x18 _amountOut) external updatePeriodState returns (SD59x18) {
    (SD59x18 amountIn, ) = _computeExactAmountIn(_amountOut);
    return amountIn;
  }

  /// @inheritdoc ILiquidationPair
  function computeExactAmountOut(uint256 _amountIn) external updatePeriodState returns (uint256) {
    (SD59x18 amountOut, ) = _computeExactAmountOut(convert(int256(_amountIn)));
    return uint256(convert(amountOut));
  }

  function computeExactAmountOut(SD59x18 _amountIn) external updatePeriodState returns (SD59x18) {
    (SD59x18 amountOut, ) = _computeExactAmountOut(_amountIn);
    return amountOut;
  }

  /**
   * @notice Gets the exchange rate for the current time.
   * @param _phase The current phase of the auction.
   * @param _percentCompleted The percent completed of the current period.
   * @param _exchangeRateSmoothing The smoothing factor for the exchange rate.
   * @param _phaseTwoRangeRate The slope of the line during phase 2.
   * @param _phaseTwoDurationPercentHalved The duration of phase 2 divided by 2.
   * @param _targetExchangeRate The target exchange rate.
   * @return exchangeRate The exchange rate for the current time.
   */
  function getExchangeRate(
    uint8 _phase,
    SD59x18 _percentCompleted,
    SD59x18 _exchangeRateSmoothing,
    SD59x18 _phaseTwoRangeRate,
    SD59x18 _phaseTwoDurationPercentHalved,
    SD59x18 _targetExchangeRate
  ) public view returns (SD59x18 exchangeRate) {
    return
      LiquidatorLib.getExchangeRate(
        _phase,
        _percentCompleted,
        _exchangeRateSmoothing,
        _phaseTwoRangeRate,
        _phaseTwoDurationPercentHalved,
        _targetExchangeRate
      );
  }

  /* ============ Internal Functions ============ */

  /**
   * @notice Updates the state of the auction.
   * @param _account The account to send the tokens to.
   * @param _amountIn The amount of tokens being sent in.
   * @param _amountOutMin The minimum amount of tokens being sent out.
   * @return The amount of tokens being sent out.
   */
  function _swapExactAmountIn(
    address _account,
    SD59x18 _amountIn,
    SD59x18 _amountOutMin
  ) internal returns (SD59x18) {
    (SD59x18 amountOut, SD59x18 exchangeRate) = _computeExactAmountOut(_amountIn);

    require(amountOut.gte(_amountOutMin), "LiquidationPair/insufficient-amount-out");
    _updateState(amountOut, exchangeRate);
    _swap(_account, amountOut, _amountIn);

    return amountOut;
  }

  /**
   * @notice Swaps an exact amount of tokens out for an amount of tokens in.
   * @param _account The account to send the tokens to.
   * @param _amountOut The amount of tokens being sent out.
   * @param _amountInMax The maximum amount of tokens sent in.
   * @return The amount of tokens sent in.
   */
  function _swapExactAmountOut(
    address _account,
    SD59x18 _amountOut,
    SD59x18 _amountInMax
  ) internal returns (SD59x18) {
    (SD59x18 amountIn, SD59x18 exchangeRate) = _computeExactAmountIn(_amountOut);

    require(amountIn.lte(_amountInMax), "LiquidationPair/amount-in-exceeds-max");
    _updateState(_amountOut, exchangeRate);
    _swap(_account, _amountOut, amountIn);

    return amountIn;
  }

  /**
   * @notice Updates the state of the current auction.
   * @param _amountOut The amount of tokens being sent out.
   * @param _exchangeRate The exchange rate for the current swap.
   * @dev The state is updated after a successful swap and preps the state for the next period.
   */
  function _updateState(SD59x18 _amountOut, SD59x18 _exchangeRate) internal {
    if (_exchangeRate.gt(convert(0))) {
      nextTargetExchangeRate = nextTargetExchangeRate.add(_exchangeRate).div(convert(2));
    }
    maxAmountOutThisPeriod = maxAmountOutThisPeriod.sub(_amountOut);
  }

  /**
   * @notice Calculate the slope of the line for phase 2.
   * @dev Traversing from: targetExchangeRate - (phaseTwoRangePercentHalved % * targetExchangeRate) to targetExchangeRate + (phaseTwoRangePercentHalved % * targetExchangeRate)
   * @return The slope of the line for phase 2.
   */
  function _getPhaseTwoRangeRate() internal view returns (SD59x18) {
    return targetExchangeRate.mul(phaseTwoRangePercentHalved).div(convert(1000));
  }

  /**
   * @notice Computes the amount of tokens to send for a given amount of tokens to receive.
   * @dev If we shortcircuit due to an over/underflow, we return exchange rate of 0. No update to stored target exchagne rate is taken in this case.
   * @param _amountOut The amount of tokens to receive.
   * @return The amount of tokens to receive.
   * @return The exchange rate for these tokens.
   */
  function _computeExactAmountIn(SD59x18 _amountOut) internal returns (SD59x18, SD59x18) {
    (SD59x18 percentCompleted, uint8 phase) = _getAuctionState();

    (bool success, bytes memory returnData) = address(this).delegatecall(
      abi.encodeWithSelector(
        this.getExchangeRate.selector,
        phase,
        percentCompleted,
        exchangeRateSmoothing,
        _getPhaseTwoRangeRate(),
        phaseTwoDurationPercentHalved,
        targetExchangeRate
      )
    );

    SD59x18 exchangeRate;
    if (success) {
      exchangeRate = abi.decode(returnData, (SD59x18));
      // If exchange rate is negative, short circuit
      if (exchangeRate.lte(convert(0))) {
        return (MAX_SD59x18, convert(0));
      }
    } else if (percentCompleted.gte(convert(50))) {
      // If we're greater than 50% completed, then it's an underflow
      // Exchange rate at 50% is always >= 0, exchange rate is increasing
      return (convert(0), convert(0));
    } else {
      return (MAX_SD59x18, convert(0));
    }

    return (_amountOut.div(exchangeRate), exchangeRate);
  }

  /**
   * @notice Computes the amount of tokens to receive for a given amount of tokens to send.
   * @dev If we shortcircuit due to an over/underflow, we return exchange rate of 0. No update to stored target exchagne rate is taken in this case.
   * @param _amountIn The amount of tokens to send.
   * @return The amount of tokens to receive.
   * @return The exchange rate for these tokens.
   */
  function _computeExactAmountOut(SD59x18 _amountIn) internal returns (SD59x18, SD59x18) {
    (SD59x18 percentCompleted, uint8 phase) = _getAuctionState();

    (bool success, bytes memory returnData) = address(this).delegatecall(
      abi.encodeWithSelector(
        this.getExchangeRate.selector,
        phase,
        percentCompleted,
        exchangeRateSmoothing,
        _getPhaseTwoRangeRate(),
        phaseTwoDurationPercentHalved,
        targetExchangeRate
      )
    );

    SD59x18 exchangeRate;
    if (success) {
      exchangeRate = abi.decode(returnData, (SD59x18));
      // If exchange rate is negative, force to 0
      if (exchangeRate.lte(convert(0))) {
        return (convert(0), convert(0));
      }
    } else if (percentCompleted.lte(convert(50))) {
      // If we're less than 50% completed, then it's an underflow
      // Exchange rate at 50% is always >= 0, exchange rate is increasing
      return (convert(0), convert(0));
    } else {
      return (MAX_SD59x18, convert(0));
    }

    return (_amountIn.mul(exchangeRate), exchangeRate);
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

  /**
   * @notice Gets the current state of the auction.
   * @return percentCompleted The percent of the current period that has elapsed.
   * @return phase The current phase that the auction is in.
   * @dev The phase dictates the exchange rate curve.
   */
  function _getAuctionState() internal view returns (SD59x18 percentCompleted, uint8 phase) {
    uint32 timeElapsed = _getTimeElapsed();

    percentCompleted = timeElapsed > 0
      ? convert(int(uint(timeElapsed))).div(convert(int(uint(periodLength)))).mul(convert(100))
      : convert(0);

    // NOTE: Prioritize phase 2 on overlap
    if (percentCompleted.lt(phaseOneEndPercent)) {
      phase = 1;
    } else if (percentCompleted.lte(phaseTwoEndPercent)) {
      phase = 2;
    } else {
      phase = 3;
    }
  }

  /**
   * @notice Gets the time elapsed since the start of the current period.
   * @return The time elapsed since the start of the current period.
   */
  function _getTimeElapsed() internal view returns (uint32) {
    return
      uint32(block.timestamp) > periodOffset
        ? uint32(block.timestamp) - _getPeriodStartTimestamp(uint32(block.timestamp))
        : 0;
  }

  /**
   * @notice Gets the timestamp for the start of the period that the given timestamp falls in.
   * @param _timestamp The timestamp to get the current period start for.
   * @return timestamp The timestamp for the start of the period that the given timestamp falls in.
   */
  function _getPeriodStartTimestamp(uint32 _timestamp) private view returns (uint32 timestamp) {
    uint32 period = _getTimestampPeriod(_timestamp);
    return period > 0 ? periodOffset + ((period - 1) * periodLength) : 0;
  }

  /**
   * @notice Gets the period that the given timestamp falls in.
   * @param _timestamp The timestamp to get the current period for.
   * @return period The period that the given timestamp falls in.
   */
  function _getTimestampPeriod(uint32 _timestamp) private view returns (uint32 period) {
    if (_timestamp <= periodOffset) {
      return 0;
    }
    // Shrink by 1 to ensure periods end on a multiple of periodLength.
    // Increase by 1 to start periods at # 1.
    return ((_timestamp - periodOffset - 1) / periodLength) + 1;
  }
}
