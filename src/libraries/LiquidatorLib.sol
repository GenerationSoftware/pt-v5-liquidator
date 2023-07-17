// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { console2 } from "forge-std/console2.sol";

import "openzeppelin/token/ERC20/IERC20.sol";
import { SD59x18, convert, wrap } from "prb-math/SD59x18.sol";

library LiquidatorLib {
  /**
   * @notice Gets the exchange rate for the current time.
   * @param phase The current phase of the auction.
   * @param percentCompleted The percent completed of the current period.
   * @param exchangeRateSmoothing The smoothing factor for the exchange rate.
   * @param phaseTwoRangeRate The slope of the line during phase 2.
   * @param phaseTwoDurationPercentHalved The duration of phase 2 divided by 2.
   * @param targetExchangeRate The target exchange rate.
   * @return exchangeRate The exchange rate for the current time.
   */
  function getExchangeRate(
    uint8 phase,
    SD59x18 percentCompleted,
    SD59x18 exchangeRateSmoothing,
    SD59x18 phaseTwoRangeRate,
    SD59x18 phaseTwoDurationPercentHalved,
    SD59x18 targetExchangeRate
  ) internal view returns (SD59x18 exchangeRate) {
    if (phase == 1) {
      exchangeRate = getExchangeRatePhase1(
        percentCompleted,
        exchangeRateSmoothing,
        phaseTwoRangeRate,
        phaseTwoDurationPercentHalved,
        targetExchangeRate
      );
    } else if (phase == 2) {
      exchangeRate = getExchangeRatePhase2(percentCompleted, phaseTwoRangeRate, targetExchangeRate);
    } else if (phase == 3) {
      exchangeRate = getExchangeRatePhase3(
        percentCompleted,
        exchangeRateSmoothing,
        phaseTwoRangeRate,
        phaseTwoDurationPercentHalved,
        targetExchangeRate
      );
    } else {
      revert("LiquidationPair/invalid-phase");
    }
  }

  /**
   * @notice Gets the exchange rate for phase 1.
   * @dev The exchange rate for phase 1 goes from 0 -> some percentage of the target exchange rate as the auction approaches the transition to phase 2.
   * @dev f(x) = (1 / (-percentCompleted) / (exchangeRateSmoothing * (50 - phaseTwoDurationPercentHalvedScaled))) + targetExchangeRate - phaseTwoRangeRate * phaseTwoDurationPercentHalvedScaled + exchangeRateSmoothing
   * @param percentCompleted The percent completed of the current period.
   * @param exchangeRateSmoothing The smoothing factor for the exchange rate.
   * @param phaseTwoRangeRate The slope of the line during phase 2.
   * @param phaseTwoDurationPercentHalved The duration of phase 2 divided by 2.
   * @param targetExchangeRate The target exchange rate.
   * @return exchangeRate The exchange rate for the current time.
   */
  function getExchangeRatePhase1(
    SD59x18 percentCompleted,
    SD59x18 exchangeRateSmoothing,
    SD59x18 phaseTwoRangeRate,
    SD59x18 phaseTwoDurationPercentHalved,
    SD59x18 targetExchangeRate
  ) internal pure returns (SD59x18 exchangeRate) {
    exchangeRate = convert(1)
      .div(
        percentCompleted.mul(convert(-1)).div(
          exchangeRateSmoothing.mul(convert(50).sub(phaseTwoDurationPercentHalved))
        )
      )
      .add(
        targetExchangeRate.sub(phaseTwoRangeRate.mul(phaseTwoDurationPercentHalved)).add(
          exchangeRateSmoothing
        )
      );
    // console2.log("~~~");
    // console2.log("percentCompleted", convert(percentCompleted));
    // console2.log("exchangeRateSmoothing", SD59x18.unwrap(exchangeRateSmoothing));
    // console2.log("phaseTwoRangeRate", SD59x18.unwrap(phaseTwoRangeRate));
    // console2.log("phaseTwoDurationPercentHalved", SD59x18.unwrap(phaseTwoDurationPercentHalved));
    // console2.log("targetExchangeRate", SD59x18.unwrap(targetExchangeRate));
    // console2.log("exchangeRate", SD59x18.unwrap(exchangeRate));
  }

  /**
   * @notice Gets the exchange rate for phase 2.
   * @dev The exchange rate for phase 2 traverses from -X% of the target exchange rate to +X% of the target exchange rate linearly over the duration of phase 2.
   * @dev f(x)= targetExchangeRate + phaseTwoRangeRate * (x - 50)
   * @param percentCompleted The percent completed of the current period.
   * @param phaseTwoRangeRate The slope of the line during phase 2.
   * @param targetExchangeRate The target exchange rate.
   * @return exchangeRate The exchange rate for the current time.
   */
  function getExchangeRatePhase2(
    SD59x18 percentCompleted,
    SD59x18 phaseTwoRangeRate,
    SD59x18 targetExchangeRate
  ) internal pure returns (SD59x18 exchangeRate) {
    exchangeRate = targetExchangeRate.add(phaseTwoRangeRate.mul(percentCompleted.sub(convert(50))));
    // console2.log("~~~");
    // console2.log("percentCompleted", convert(percentCompleted));
    // console2.log("phaseTwoRangeRate", SD59x18.unwrap(phaseTwoRangeRate));
    // console2.log("targetExchangeRate", SD59x18.unwrap(targetExchangeRate));
    // console2.log("exchangeRate", SD59x18.unwrap(exchangeRate));
  }

  /**
   * @notice Gets the exchange rate for phase 3.
   * @dev The exchange rate for phase 3 goes from some percentage of the target exchange rate to infinity as the auction approaches 100% completion.
   * @dev f(x) = (1 / (percentCompleted - 100) / (exchangeRateSmoothing * (50 - phaseTwoDurationPercentHalvedScaled))) + targetExchangeRate + phaseTwoRangeRate * phaseTwoDurationPercentHalvedScaled - exchangeRateSmoothing
   * @param percentCompleted The percent completed of the current period.
   * @param exchangeRateSmoothing The smoothing factor for the exchange rate.
   * @param phaseTwoRangeRate The slope of the line during phase 2.
   * @param phaseTwoDurationPercentHalved The duration of phase 2 divided by 2.
   * @param targetExchangeRate The target exchange rate.
   * @return exchangeRate The exchange rate for the current time.
   */
  function getExchangeRatePhase3(
    SD59x18 percentCompleted,
    SD59x18 exchangeRateSmoothing,
    SD59x18 phaseTwoRangeRate,
    SD59x18 phaseTwoDurationPercentHalved,
    SD59x18 targetExchangeRate
  ) internal pure returns (SD59x18 exchangeRate) {
    exchangeRate = convert(-1)
      .div(
        percentCompleted.sub(convert(100)).div(
          exchangeRateSmoothing.mul(convert(50).sub(phaseTwoDurationPercentHalved))
        )
      )
      .add(
        targetExchangeRate.add(phaseTwoRangeRate.mul(phaseTwoDurationPercentHalved)).sub(
          exchangeRateSmoothing
        )
      );

    // console2.log("~~~");
    // console2.log("percentCompleted", convert(percentCompleted));
    // console2.log("exchangeRateSmoothing", SD59x18.unwrap(exchangeRateSmoothing));
    // console2.log("phaseTwoRangeRate", SD59x18.unwrap(phaseTwoRangeRate));
    // console2.log("phaseTwoDurationPercentHalved", SD59x18.unwrap(phaseTwoDurationPercentHalved));
    // console2.log("targetExchangeRate", SD59x18.unwrap(targetExchangeRate));
    // console2.log("exchangeRate", SD59x18.unwrap(exchangeRate));
  }
}
