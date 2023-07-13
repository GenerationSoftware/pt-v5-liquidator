// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";

import { LiquidationPair } from "./LiquidationPair.sol";
import { SD59x18 } from "prb-math/SD59x18.sol";

/**
 * @title PoolTogether Liquidation Pair Factory
 * @author PoolTogether Inc. Team
 * @notice A facotry to deploy LiquidationPair contracts.
 */
contract LiquidationPairFactory {
  /* ============ Events ============ */

  event PairCreated(
    LiquidationPair indexed liquidator,
    ILiquidationSource indexed source,
    address indexed tokenIn,
    address tokenOut,
    SD59x18 initialTargetExchangeRate,
    SD59x18 phaseTwoDurationPercent,
    SD59x18 phaseTwoRangePercent
  );

  /* ============ Variables ============ */

  /// @notice All LiquidationPair deployed by this factory.
  LiquidationPair[] public allPairs;

  /// @notice Sets the period of liquidations.
  uint32 public immutable periodLength;

  /// @notice Sets the beginning timestamp for the first period.
  /// @dev Ensure that the periodOffset is in the past.
  uint32 public immutable periodOffset;

  /* ============ Mappings ============ */

  /**
   * @notice Mapping to verify if a LiquidationPair has been deployed via this factory.
   * @dev LiquidationPair address => boolean
   */
  mapping(LiquidationPair => bool) public deployedPairs;

  /* ============ Constructor ============ */
  constructor(uint32 _periodLength, uint32 _periodOffset) {
    periodLength = _periodLength;
    periodOffset = _periodOffset;
  }

  /* ============ External Functions ============ */

  function createPair(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    SD59x18 _initialTargetExchangeRate,
    SD59x18 _phaseTwoDurationPercent,
    SD59x18 _phaseTwoRangePercent
  ) external returns (LiquidationPair) {
    LiquidationPair _liquidationPair = new LiquidationPair(
      _source,
      _tokenIn,
      _tokenOut,
      _initialTargetExchangeRate,
      _phaseTwoDurationPercent,
      _phaseTwoRangePercent,
      periodLength,
      periodOffset
    );

    allPairs.push(_liquidationPair);
    deployedPairs[_liquidationPair] = true;

    emit PairCreated(
      _liquidationPair,
      _source,
      _tokenIn,
      _tokenOut,
      _initialTargetExchangeRate,
      _phaseTwoDurationPercent,
      _phaseTwoRangePercent
    );

    return _liquidationPair;
  }

  /**
   * @notice Total number of LiquidationPair deployed by this factory.
   * @return Number of LiquidationPair deployed by this factory.
   */
  function totalPairs() external view returns (uint256) {
    return allPairs.length;
  }
}
