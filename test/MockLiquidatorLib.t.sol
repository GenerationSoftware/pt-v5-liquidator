// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { SD59x18, convert, toSD59x18 } from "prb-math/SD59x18.sol";

import { BaseSetup } from "./utils/BaseSetup.sol";
import { MockLiquidatorLib } from "./mocks/MockLiquidatorLib.sol";
import { LiquidatorLib } from "../src/libraries/LiquidatorLib.sol";

contract BaseLiquidatorLibTest is BaseSetup {
  /* ============ Variables ============ */

  MockLiquidatorLib public mockLiquidatorLib;
  SD59x18 defaultExchangeRateSmoothing = convert(5);
  SD59x18 defaultDiscoveryRate = LiquidatorLib.toSD59x18Percentage(20);
  SD59x18 defaultDiscoveryDelta = convert(20);
  SD59x18 defaultTargetExchangeRate = convert(1);

  /* ============ Set up ============ */

  function setUp() public virtual override {
    super.setUp();
    mockLiquidatorLib = new MockLiquidatorLib();
  }

  function testGetExchangeRatePhase1_PhaseTransition() public {
    SD59x18 exchangeRate;
    SD59x18 percentCompleted = convert(30);
    int256 expectedExchangeRate = -3e18;

    exchangeRate = mockLiquidatorLib.getExchangeRatePhase1(
      percentCompleted,
      defaultExchangeRateSmoothing,
      defaultDiscoveryRate,
      defaultDiscoveryDelta,
      defaultTargetExchangeRate
    );
    assertEq(SD59x18.unwrap(exchangeRate), expectedExchangeRate);
    exchangeRate = mockLiquidatorLib.getExchangeRatePhase2(
      percentCompleted,
      defaultDiscoveryRate,
      defaultTargetExchangeRate
    );
    assertEq(SD59x18.unwrap(exchangeRate), expectedExchangeRate);
  }

  function testGetExchangeRatePhase2_Centered() public {
    SD59x18 exchangeRate;
    exchangeRate = mockLiquidatorLib.getExchangeRatePhase2(
      convert(50),
      defaultDiscoveryRate,
      defaultTargetExchangeRate
    );
    assertEq(SD59x18.unwrap(exchangeRate), 1e18);
  }

  function testGetExchangeRatePhase3_PhaseTransition() public {
    SD59x18 exchangeRate;
    SD59x18 percentCompleted = convert(70);
    int256 expectedExchangeRate = 5e18;

    exchangeRate = mockLiquidatorLib.getExchangeRatePhase3(
      percentCompleted,
      defaultExchangeRateSmoothing,
      defaultDiscoveryRate,
      defaultDiscoveryDelta,
      defaultTargetExchangeRate
    );
    assertEq(SD59x18.unwrap(exchangeRate), expectedExchangeRate);
    exchangeRate = mockLiquidatorLib.getExchangeRatePhase2(
      percentCompleted,
      defaultDiscoveryRate,
      defaultTargetExchangeRate
    );
    assertEq(SD59x18.unwrap(exchangeRate), expectedExchangeRate);
  }
}
