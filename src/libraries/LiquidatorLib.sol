// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { console2 } from "forge-std/console2.sol";

import "openzeppelin/token/ERC20/IERC20.sol";
import { SD59x18, convert, wrap } from "prb-math/SD59x18.sol";

library LiquidatorLib {
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

  function getExchangeRatePhase1(
    SD59x18 percentCompleted,
    SD59x18 exchangeRateSmoothing,
    SD59x18 phaseTwoRangeRate,
    SD59x18 phaseTwoDurationPercentHalved,
    SD59x18 targetExchangeRate
  ) internal view returns (SD59x18 exchangeRate) {
    // f(x) = (1 / (-percentCompleted) / (exchangeRateSmoothing * (50 - phaseTwoDurationPercentHalvedScaled))) + targetExchangeRate - phaseTwoRangeRate * phaseTwoDurationPercentHalvedScaled + exchangeRateSmoothing

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

  function getExchangeRatePhase2(
    SD59x18 percentCompleted,
    SD59x18 phaseTwoRangeRate,
    SD59x18 targetExchangeRate
  ) internal view returns (SD59x18 exchangeRate) {
    // f(x)= targetExchangeRate + phaseTwoRangeRate * (x - 50)
    exchangeRate = targetExchangeRate.add(phaseTwoRangeRate.mul(percentCompleted.sub(convert(50))));
    // console2.log("~~~");
    // console2.log("percentCompleted", convert(percentCompleted));
    // console2.log("phaseTwoRangeRate", SD59x18.unwrap(phaseTwoRangeRate));
    // console2.log("targetExchangeRate", SD59x18.unwrap(targetExchangeRate));
    // console2.log("exchangeRate", SD59x18.unwrap(exchangeRate));
  }

  function getExchangeRatePhase3(
    SD59x18 percentCompleted,
    SD59x18 exchangeRateSmoothing,
    SD59x18 phaseTwoRangeRate,
    SD59x18 phaseTwoDurationPercentHalved,
    SD59x18 targetExchangeRate
  ) internal view returns (SD59x18 exchangeRate) {
    // f(x) = (1 / (percentCompleted - 100) / (exchangeRateSmoothing * (50 - phaseTwoDurationPercentHalvedScaled))) + targetExchangeRate + phaseTwoRangeRate * phaseTwoDurationPercentHalvedScaled - exchangeRateSmoothing

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
