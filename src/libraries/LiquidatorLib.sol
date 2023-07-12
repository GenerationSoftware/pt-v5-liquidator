// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { console2 } from "forge-std/console2.sol";

import "openzeppelin/token/ERC20/IERC20.sol";
import { SD59x18, convert, wrap } from "prb-math/SD59x18.sol";

library LiquidatorLib {
  function computeAmount(SD59x18 _amountOut, SD59x18 exchangeRate) internal pure returns (SD59x18) {
    return _amountOut.mul(exchangeRate);
  }

  function getExchangeRate(
    uint8 phase,
    SD59x18 percentCompleted,
    SD59x18 exchangeRateSmoothing,
    SD59x18 discoveryRate,
    SD59x18 discoveryDeltaPercent,
    SD59x18 targetExchangeRate
  ) internal view returns (SD59x18 exchangeRate) {
    if (phase == 1) {
      exchangeRate = getExchangeRatePhase1(
        percentCompleted,
        exchangeRateSmoothing,
        discoveryRate,
        discoveryDeltaPercent,
        targetExchangeRate
      );
    } else if (phase == 2) {
      exchangeRate = getExchangeRatePhase2(percentCompleted, discoveryRate, targetExchangeRate);
    } else if (phase == 3) {
      exchangeRate = getExchangeRatePhase3(
        percentCompleted,
        exchangeRateSmoothing,
        discoveryRate,
        discoveryDeltaPercent,
        targetExchangeRate
      );
    } else {
      revert("LiquidationPair/invalid-phase");
    }
  }

  function getExchangeRatePhase1(
    SD59x18 percentCompleted,
    SD59x18 exchangeRateSmoothing,
    SD59x18 discoveryRate,
    SD59x18 discoveryDeltaPercent,
    SD59x18 targetExchangeRate
  ) internal view returns (SD59x18 exchangeRate) {
    // f(x) = (1 / (-percentCompleted) / (exchangeRateSmoothing * (50 - discoveryDeltaPercent))) + targetExchangeRate - discoveryRate * discoveryDeltaPercent + exchangeRateSmoothing
    exchangeRate = convert(1)
      .div(
        percentCompleted.mul(convert(-1)).div(
          exchangeRateSmoothing.mul(convert(50).sub(discoveryDeltaPercent))
        )
      )
      .add(
        targetExchangeRate.sub(discoveryRate.mul(discoveryDeltaPercent)).add(exchangeRateSmoothing)
      );
    // console2.log("exchangeRate", SD59x18.unwrap(exchangeRate));
  }

  function getExchangeRatePhase2(
    SD59x18 percentCompleted,
    SD59x18 discoveryRate,
    SD59x18 targetExchangeRate
  ) internal view returns (SD59x18 exchangeRate) {
    // f(x)= targetExchangeRate + discoveryRate * (x - 50)
    exchangeRate = targetExchangeRate.add(discoveryRate.mul(percentCompleted.sub(convert(50))));
    // console2.log("exchangeRate", SD59x18.unwrap(exchangeRate));
  }

  function getExchangeRatePhase3(
    SD59x18 percentCompleted,
    SD59x18 exchangeRateSmoothing,
    SD59x18 discoveryRate,
    SD59x18 discoveryDeltaPercent,
    SD59x18 targetExchangeRate
  ) internal view returns (SD59x18 exchangeRate) {
    // f(x) = (1 / (percentCompleted - 100) / (exchangeRateSmoothing * (50 - discoveryDeltaPercent))) + targetExchangeRate + discoveryRate * discoveryDeltaPercent - exchangeRateSmoothing

    exchangeRate = convert(-1)
      .div(
        percentCompleted.sub(convert(100)).div(
          exchangeRateSmoothing.mul(convert(50).sub(discoveryDeltaPercent))
        )
      )
      .add(
        targetExchangeRate.add(discoveryRate.mul(discoveryDeltaPercent)).sub(exchangeRateSmoothing)
      );
    // console2.log("exchangeRate", SD59x18.unwrap(exchangeRate));
  }

  function toSD59x18Percentage(int256 percentage) internal pure returns (SD59x18) {
    return wrap(percentage * 10 ** 16);
  }
}
