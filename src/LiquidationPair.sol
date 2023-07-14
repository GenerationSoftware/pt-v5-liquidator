// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";
import { ILiquidationPair } from "v5-liquidator-interfaces/ILiquidationPair.sol";

import { LiquidatorLib } from "./libraries/LiquidatorLib.sol";
import { SD59x18, convert, MAX_SD59x18 } from "prb-math/SD59x18.sol";

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
contract LiquidationPair is ILiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source;
  address public immutable tokenIn;
  address public immutable tokenOut;
  SD59x18 public targetExchangeRate; // tokenIn/tokenOut.
  SD59x18 public nextTargetExchangeRate; // tokenIn/tokenOut.
  uint32 public lastSwapPeriod; // The period of the last swap. Used for determining when to update the target exchange rate.
  SD59x18 public phaseTwoDurationPercent; // % of time to traverse during phase 2.
  SD59x18 public phaseTwoRangePercent; // % of target exchange rate to traverse during phase 2.
  SD59x18 public exchangeRateSmoothing = convert(5); // Smooths the curve when the exchange rate is in phase 1 or phase 3.

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
  function maxAmountIn() external view returns (uint256) {}

  /// @inheritdoc ILiquidationPair
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

  /* ============ External Methods ============ */

  function getAuctionState() external view returns (SD59x18 percentCompleted, uint8 phase) {
    return _getAuctionState();
  }

  /// @inheritdoc ILiquidationPair
  function swapExactAmountIn(
    address _receiver,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) external returns (uint256) {
    return
      uint(
        convert(_swapExactAmountIn(_receiver, convert(int(_amountIn)), convert(int(_amountOutMin))))
      );
  }

  function swapExactAmountIn(
    address _account,
    SD59x18 _amountIn,
    SD59x18 _amountOutMin
  ) external returns (SD59x18) {
    return _swapExactAmountIn(_account, _amountIn, _amountOutMin);
  }

  /// @inheritdoc ILiquidationPair
  function swapExactAmountOut(
    address _receiver,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external returns (uint256) {
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
  ) external returns (SD59x18) {
    return _swapExactAmountOut(_account, _amountOut, _amountInMax);
  }

  /// @inheritdoc ILiquidationPair
  function computeExactAmountIn(uint256 _amountOut) external returns (uint256) {
    (SD59x18 amountIn, ) = _computeExactAmountIn(convert(int256(_amountOut)));
    return uint256(convert(amountIn));
  }

  function computeExactAmountIn(SD59x18 _amountOut) external returns (SD59x18) {
    (SD59x18 amountIn, ) = _computeExactAmountIn(_amountOut);
    return amountIn;
  }

  /// @inheritdoc ILiquidationPair
  function computeExactAmountOut(uint256 _amountIn) external returns (uint256) {
    (SD59x18 amountOut, ) = _computeExactAmountOut(convert(int256(_amountIn)));
    return uint256(convert(amountOut));
  }

  function computeExactAmountOut(SD59x18 _amountIn) external returns (SD59x18) {
    (SD59x18 amountOut, ) = _computeExactAmountOut(_amountIn);
    return amountOut;
  }

  function computeExactAmountIn(
    SD59x18 _amountOut,
    SD59x18 exchangeRate
  ) external pure returns (SD59x18) {
    return _computeExactAmountIn(_amountOut, exchangeRate);
  }

  function computeExactAmountOut(
    SD59x18 _amountIn,
    SD59x18 exchangeRate
  ) external pure returns (SD59x18) {
    return _computeExactAmountOut(_amountIn, exchangeRate);
  }

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

  function _swapExactAmountIn(
    address _account,
    SD59x18 _amountIn,
    SD59x18 _amountOutMin
  ) internal returns (SD59x18) {
    uint32 period = _getTimestampPeriod(uint32(block.timestamp));

    (SD59x18 amountOut, SD59x18 exchangeRate) = _computeExactAmountOut(_amountIn);

    require(amountOut.gte(_amountOutMin), "LiquidationPair/insufficient-amount-out");
    if (exchangeRate.gt(convert(0))) {
      _updateNextTargetExchangeRate(exchangeRate);
    }
    _updateLastSwapPeriod(period);
    _swap(_account, amountOut, _amountIn);

    return amountOut;
  }

  function _swapExactAmountOut(
    address _account,
    SD59x18 _amountOut,
    SD59x18 _amountInMax
  ) internal returns (SD59x18) {
    uint32 period = _getTimestampPeriod(uint32(block.timestamp));

    (SD59x18 amountIn, SD59x18 exchangeRate) = _computeExactAmountIn(_amountOut);

    require(amountIn.lte(_amountInMax), "LiquidationPair/amount-in-exceeds-max");
    if (exchangeRate.gt(convert(0))) {
      _updateNextTargetExchangeRate(exchangeRate);
    }
    _updateLastSwapPeriod(period);
    _swap(_account, _amountOut, amountIn);

    return amountIn;
  }

  function _updateNextTargetExchangeRate(SD59x18 _exchangeRate) internal {
    nextTargetExchangeRate = nextTargetExchangeRate.add(_exchangeRate).div(convert(2));
  }

  function _updateLastSwapPeriod(uint32 _period) internal {
    if (_period > lastSwapPeriod) {
      lastSwapPeriod = _period;
    }
  }

  function _getTargetExchangeRate() internal returns (SD59x18) {
    uint32 period = _getTimestampPeriod(uint32(block.timestamp));
    if (period > lastSwapPeriod) {
      targetExchangeRate = nextTargetExchangeRate;
      return targetExchangeRate;
    }
    return targetExchangeRate;
  }

  // Calculate the slope of the curve for phase 2.
  // Traversing from:
  //    targetExchangeRate - (phaseTwoRangePercentHalved % * targetExchangeRate)
  //    to
  //    targetExchangeRate + (phaseTwoRangePercentHalved % * targetExchangeRate)
  function _getPhaseTwoRangeRate() internal view returns (SD59x18) {
    return targetExchangeRate.mul(phaseTwoRangePercentHalved).div(convert(1000));
  }

  // NOTE: If we shortcircuit do to an over/underflow, we return exchange rate of 0. No update action is taken.
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
        _getTargetExchangeRate()
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

    return (_computeExactAmountIn(_amountOut, exchangeRate), exchangeRate);
  }

  function _computeExactAmountIn(
    SD59x18 _amountOut,
    SD59x18 exchangeRate
  ) internal pure returns (SD59x18) {
    return _amountOut.div(exchangeRate);
  }

  // NOTE: If we shortcircuit do to an over/underflow, we return exchange rate of 0. No update action is taken.
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
        _getTargetExchangeRate()
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

    return (_computeExactAmountOut(_amountIn, exchangeRate), exchangeRate);
  }

  function _computeExactAmountOut(
    SD59x18 _amountIn,
    SD59x18 exchangeRate
  ) internal pure returns (SD59x18) {
    return _amountIn.mul(exchangeRate);
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

    // NOTE: Prioritize phase 2 on overlap
    if (percentCompleted.lt(phaseOneEndPercent)) {
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
