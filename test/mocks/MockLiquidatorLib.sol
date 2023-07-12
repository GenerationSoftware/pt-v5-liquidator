// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../../src/libraries/LiquidatorLib.sol";

// Note: Need to store the results from the library in a variable to be picked up by forge coverage
// See: https://github.com/foundry-rs/foundry/pull/3128#issuecomment-1241245086

contract MockLiquidatorLib {
  function getExchangeRatePhase1(
    SD59x18 percentCompleted,
    SD59x18 exchangeRateSmoothing,
    SD59x18 discoveryRate,
    SD59x18 discoveryDelta,
    SD59x18 targetExchangeRate
  ) public view returns (SD59x18) {
    SD59x18 exchangeRate = LiquidatorLib.getExchangeRatePhase1(
      percentCompleted,
      exchangeRateSmoothing,
      discoveryRate,
      discoveryDelta,
      targetExchangeRate
    );
    return exchangeRate;
  }

  function getExchangeRatePhase2(
    SD59x18 percentCompleted,
    SD59x18 discoveryRate,
    SD59x18 targetExchangeRate
  ) public view returns (SD59x18) {
    SD59x18 exchangeRate = LiquidatorLib.getExchangeRatePhase2(
      percentCompleted,
      discoveryRate,
      targetExchangeRate
    );
    return exchangeRate;
  }

  function getExchangeRatePhase3(
    SD59x18 percentCompleted,
    SD59x18 exchangeRateSmoothing,
    SD59x18 discoveryRate,
    SD59x18 discoveryDelta,
    SD59x18 targetExchangeRate
  ) public view returns (SD59x18) {
    SD59x18 exchangeRate = LiquidatorLib.getExchangeRatePhase3(
      percentCompleted,
      exchangeRateSmoothing,
      discoveryRate,
      discoveryDelta,
      targetExchangeRate
    );
    return exchangeRate;
  }
}
