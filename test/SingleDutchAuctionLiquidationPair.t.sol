// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { BaseSetup } from "./utils/BaseSetup.sol";
import { ILiquidationSource } from "../src/interfaces/ILiquidationSource.sol";
import { LiquidationPair } from "../src/LiquidationPair.sol";
import { SD59x18, convert, uMAX_SD59x18 } from "prb-math/SD59x18.sol";
import { Utils } from "./utils/Utils.sol";
import { LiquidatorLib } from "../src/libraries/LiquidatorLib.sol";

contract SingleDutchAuctionLiquidationPair is BaseSetup {
  uint32 public drawLength = 1 days;
  uint32 public drawOffset = 1 days;
  address public tokenIn;
  address public tokenOut;
  address public source;
  address public target;
  SD59x18 defaultTargetExchangeRate = convert(1);
  SD59x18 defaultDiscoveryRate = LiquidatorLib.toSD59x18Percentage(20);
  SD59x18 defaultDiscoveryDeltaPercent = convert(20);
  LiquidationPair public pair;

  /* ============ Set up ============ */
  function setUp() public override {
    super.setUp();

    tokenIn = utils.generateAddress("tokenIn");
    tokenOut = utils.generateAddress("tokenOut");
    source = utils.generateAddress("source");
    target = utils.generateAddress("target");
    // Contract setup
    pair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultTargetExchangeRate,
      defaultDiscoveryDeltaPercent,
      defaultDiscoveryRate,
      drawLength,
      drawOffset
    );
  }

  function testGetTimestampPeriod() public {
    uint32 period;

    // - 1 second
    vm.warp(drawOffset - 1 seconds);
    period = pair.getTimestampPeriod();
    assertEq(period, 0);

    // Start
    vm.warp(drawOffset);
    period = pair.getTimestampPeriod();
    assertEq(period, 0);

    // + 1 second
    vm.warp(drawOffset + 1 seconds);
    period = pair.getTimestampPeriod();
    assertEq(period, 1);

    // Quarter
    vm.warp(drawOffset + drawLength / 4);
    period = pair.getTimestampPeriod();
    assertEq(period, 1);

    // Half
    vm.warp(drawOffset + drawLength / 2);
    period = pair.getTimestampPeriod();
    assertEq(period, 1);

    // Three quarters
    vm.warp(drawOffset + (drawLength * 3) / 4);
    period = pair.getTimestampPeriod();
    assertEq(period, 1);

    // End
    vm.warp(drawOffset + drawLength);
    period = pair.getTimestampPeriod();
    assertEq(period, 1);

    // + 1 second
    vm.warp(drawOffset + drawLength + 1 seconds);
    period = pair.getTimestampPeriod();
    assertEq(period, 2);
  }

  function testGetTimeElapsed() public {
    uint32 timeElapsed;

    // - 1 second
    vm.warp(drawOffset - 1 seconds);
    timeElapsed = pair.getTimeElapsed();
    assertEq(timeElapsed, 0);

    // Start
    vm.warp(drawOffset);
    timeElapsed = pair.getTimeElapsed();
    assertEq(timeElapsed, 0);

    // + 1 second
    vm.warp(drawOffset + 1 seconds);
    timeElapsed = pair.getTimeElapsed();
    assertEq(timeElapsed, 1);

    // Quarter
    vm.warp(drawOffset + drawLength / 4);
    timeElapsed = pair.getTimeElapsed();
    assertEq(timeElapsed, drawLength / 4);

    // Half
    vm.warp(drawOffset + drawLength / 2);
    timeElapsed = pair.getTimeElapsed();
    assertEq(timeElapsed, drawLength / 2);

    // Three quarters
    vm.warp(drawOffset + (drawLength * 3) / 4);
    timeElapsed = pair.getTimeElapsed();
    assertEq(timeElapsed, (drawLength * 3) / 4);

    // - 1 second
    vm.warp(drawOffset + drawLength - 1 seconds);
    timeElapsed = pair.getTimeElapsed();
    assertEq(timeElapsed, drawLength - 1);

    // End
    vm.warp(drawOffset + drawLength);
    timeElapsed = pair.getTimeElapsed();
    assertEq(timeElapsed, drawLength);

    // + 1 second
    vm.warp(drawOffset + drawLength + 1 seconds);
    timeElapsed = pair.getTimeElapsed();
    assertEq(timeElapsed, 1);
  }

  function testGetPeriodStartTimestamp() public {
    uint32 timestamp;

    // - 1 second
    vm.warp(drawOffset - 1 seconds);
    timestamp = pair.getPeriodStartTimestamp();
    assertEq(timestamp, 0);

    // Start
    vm.warp(drawOffset);
    timestamp = pair.getPeriodStartTimestamp();
    assertEq(timestamp, 0);

    // + 1 second
    vm.warp(drawOffset + 1 seconds);
    timestamp = pair.getPeriodStartTimestamp();
    assertEq(timestamp, drawOffset);

    // Quarter
    vm.warp(drawOffset + drawLength / 4);
    timestamp = pair.getPeriodStartTimestamp();
    assertEq(timestamp, drawOffset);

    // Half
    vm.warp(drawOffset + drawLength / 2);
    timestamp = pair.getPeriodStartTimestamp();
    assertEq(timestamp, drawOffset);

    // Three quarters
    vm.warp(drawOffset + (drawLength * 3) / 4);
    timestamp = pair.getPeriodStartTimestamp();
    assertEq(timestamp, drawOffset);

    // - 1 second
    vm.warp(drawOffset + drawLength - 1 seconds);
    timestamp = pair.getPeriodStartTimestamp();
    assertEq(timestamp, drawOffset);

    // End
    vm.warp(drawOffset + drawLength);
    timestamp = pair.getPeriodStartTimestamp();
    assertEq(timestamp, drawOffset);

    // + 1 second
    vm.warp(drawOffset + drawLength + 1 seconds);
    timestamp = pair.getPeriodStartTimestamp();
    assertEq(timestamp, drawOffset + drawLength);
  }

  function testGetAuctionState() public {
    SD59x18 percentCompleted;
    uint8 phase;

    // - 1 second
    vm.warp(drawOffset - 1 seconds);
    (percentCompleted, phase) = pair.getAuctionState();
    // NOTE: the state prior to or equal to periodOffset will always be 0% completed
    assertEq(SD59x18.unwrap(percentCompleted), 0); // 0%
    // NOTE: the state prior to or equal to periodOffset will always be phase 1
    assertEq(phase, 1);

    // Start
    vm.warp(drawOffset);
    (percentCompleted, phase) = pair.getAuctionState();
    assertEq(SD59x18.unwrap(percentCompleted), 0); // 0%
    assertEq(phase, 1);

    // + 1 second
    vm.warp(drawOffset + 1 seconds);
    (percentCompleted, phase) = pair.getAuctionState();
    assertEq(SD59x18.unwrap(percentCompleted), 1157407407407400); // 1/86400
    assertEq(phase, 1);

    // Quarter through
    vm.warp(drawOffset + drawLength / 4);
    (percentCompleted, phase) = pair.getAuctionState();
    assertEq(SD59x18.unwrap(percentCompleted), 25e18); // 25%
    assertEq(phase, 1);

    // Halfway through
    vm.warp(drawOffset + drawLength / 2);
    (percentCompleted, phase) = pair.getAuctionState();
    assertEq(SD59x18.unwrap(percentCompleted), 50e18); // 50%
    assertEq(phase, 2);

    // Three quarters through
    vm.warp(drawOffset + (drawLength * 3) / 4);
    (percentCompleted, phase) = pair.getAuctionState();
    assertEq(SD59x18.unwrap(percentCompleted), 75e18); // 75%
    assertEq(phase, 3);

    // - 1 second
    vm.warp(drawOffset + drawLength - 1 seconds);
    (percentCompleted, phase) = pair.getAuctionState();
    assertEq(SD59x18.unwrap(percentCompleted), 99998842592592592500); // 86399/86400
    assertEq(phase, 3);

    // End
    vm.warp(drawOffset + drawLength);
    (percentCompleted, phase) = pair.getAuctionState();
    assertEq(SD59x18.unwrap(percentCompleted), 100e18); // 100%
    assertEq(phase, 3);

    // + 1 second
    vm.warp(drawOffset + drawLength + 1 seconds);
    (percentCompleted, phase) = pair.getAuctionState();
    assertEq(SD59x18.unwrap(percentCompleted), 1157407407407400); // 1/86400
    assertEq(phase, 1);
  }

  // Exchange rate is IN per OUT
  function testComputeAmountIn_WithExchangeRate() public {
    SD59x18 amountIn;
    SD59x18 amountOut;
    SD59x18 exchangeRate;

    // 1 IN : 1 OUT
    exchangeRate = convert(1);
    // With .5 OUT -> .5 IN
    amountOut = SD59x18.wrap(50e16);
    amountIn = pair.computeAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 50e16);
    // With 1 OUT -> 1 IN
    amountOut = convert(1);
    amountIn = pair.computeAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 1e18);
    // With 2 OUT -> 2 IN
    amountOut = convert(2);
    amountIn = pair.computeAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 2e18);

    // 1 IN : 2 OUT
    exchangeRate = SD59x18.wrap(50e16);
    // With .5 OUT -> .25 IN
    amountOut = SD59x18.wrap(50e16);
    amountIn = pair.computeAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 25e16);
    // With 1 OUT -> .5 IN
    amountOut = convert(1);
    amountIn = pair.computeAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 50e16);
    // With 2 OUT -> 1 IN
    amountOut = convert(2);
    amountIn = pair.computeAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 1e18);

    // 2 IN : 1 OUT
    exchangeRate = convert(2);
    // With .5 OUT -> 1 IN
    amountOut = SD59x18.wrap(50e16);
    amountIn = pair.computeAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 1e18);
    // With 1 OUT -> 2 IN
    amountOut = convert(1);
    amountIn = pair.computeAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 2e18);
    // With 2 OUT -> 4 IN
    amountOut = convert(2);
    amountIn = pair.computeAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 4e18);
  }

  // Exchange rate is IN per OUT
  function testComputeAmountOut_WithExchangeRate() public {
    SD59x18 amountIn;
    SD59x18 amountOut;
    SD59x18 exchangeRate;

    // 1 IN : 1 OUT
    exchangeRate = convert(1);
    // With .5 IN -> .5 OUT
    amountIn = SD59x18.wrap(50e16);
    amountOut = pair.computeAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 50e16);
    // With 1 IN -> 1 OUT
    amountIn = convert(1);
    amountOut = pair.computeAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 1e18);
    // With 2 IN -> 2 OUT
    amountIn = convert(2);
    amountOut = pair.computeAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 2e18);

    // 1 IN : 2 OUT
    exchangeRate = SD59x18.wrap(50e16);
    // With .5 IN -> 1 OUT
    amountIn = SD59x18.wrap(50e16);
    amountOut = pair.computeAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 1e18);
    // With 1 IN -> 2 OUT
    amountIn = convert(1);
    amountOut = pair.computeAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 2e18);
    // With 2 IN -> 4 OUT
    amountIn = convert(2);
    amountOut = pair.computeAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 4e18);

    // 2 IN : 1 OUT
    exchangeRate = convert(2);
    // With .5 IN -> .25 OUT
    amountIn = SD59x18.wrap(50e16);
    amountOut = pair.computeAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 25e16);
    // With 1 IN -> .5 OUT
    amountIn = convert(1);
    amountOut = pair.computeAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 50e16);
    // With 2 IN -> 1 OUT
    amountIn = convert(2);
    amountOut = pair.computeAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 1e18);
  }

  function testComputeAmountIn_WithTime() public {
    SD59x18 amountIn;
    SD59x18 amountOut = convert(1);

    // - 1 second
    vm.warp(drawOffset - 1 seconds);
    amountIn = pair.computeAmountIn(amountOut);
    // NOTE: Any time prior or equal to the drawOffset should return 0
    assertEq(SD59x18.unwrap(amountIn), 0);

    // Start
    vm.warp(drawOffset);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 0);

    // + 1 second
    vm.warp(drawOffset + 1 seconds);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 0);

    // Twenty percent
    vm.warp(drawOffset + drawLength / 5);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 0);

    // Quarter
    vm.warp(drawOffset + drawLength / 4);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 0);

    // Forty percent
    vm.warp(drawOffset + (drawLength * 2) / 5);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 0);

    // Half
    vm.warp(drawOffset + drawLength / 2);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 1e18);

    // Sixty percent
    vm.warp(drawOffset + (drawLength * 3) / 5);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 3e18);

    // Three quarters
    vm.warp(drawOffset + (drawLength / 4) * 3);
    amountIn = pair.computeAmountIn(amountOut);
    // NOTE: Slight inaccuracy due to rounding
    assertEq(SD59x18.unwrap(amountIn), 6000000000000000024);

    // Eighty percent
    vm.warp(drawOffset + (drawLength * 4) / 5);
    amountIn = pair.computeAmountIn(amountOut);
    // NOTE: Slight inaccuracy due to rounding
    assertEq(SD59x18.unwrap(amountIn), 7500000000000000018);

    // - 1 second
    vm.warp(drawOffset + drawLength - 1 seconds);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 129600000000000829440000);

    // End
    vm.warp(drawOffset + drawLength);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), uMAX_SD59x18);

    // + 1 second
    vm.warp(drawOffset + drawLength + 1 seconds);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 0);
  }

  function testComputeAmountIn_WithTime_CustomPair() public {
    SD59x18 amountIn;
    SD59x18 amountOut = convert(1);

    // Center on exchange rate of 50 IN : 1 OUT
    SD59x18 targetExchangeRate = convert(50);
    // Amount to increase exchange rate by per second
    SD59x18 discoveryRate = convert(1);
    // 30 mins -> 1 hour of tailored discovery
    SD59x18 discoveryDeltaPercent = SD59x18.wrap(0.0208333333e18);

    pair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      targetExchangeRate,
      discoveryRate,
      discoveryDeltaPercent,
      drawLength,
      drawOffset
    );

    console2.log("drawOffset + drawLength / 2 - 1 hours", (drawOffset + drawLength / 2 - 1 hours));
    console2.log("drawLength", drawLength);
    console2.log("Changeover", SD59x18.unwrap(pair.phaseOneEndPercent()));

    // - 1 second
    vm.warp(drawOffset - 1 seconds);
    amountIn = pair.computeAmountIn(amountOut);
    // NOTE: Any time prior or equal to the drawOffset should return 0
    assertEq(SD59x18.unwrap(amountIn), 0);

    // Start
    vm.warp(drawOffset);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 0);

    // + 1 second
    vm.warp(drawOffset + 1 seconds);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 0);

    // Twenty percent
    vm.warp(drawOffset + drawLength / 5);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 42812499999499999997);

    // Quarter
    vm.warp(drawOffset + drawLength / 4);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 45208333332999999951);

    // Forty percent
    vm.warp(drawOffset + (drawLength * 2) / 5);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 48802083333249999999);

    //////////////////////////////////////////////////////////

    // Start of 1 hour 10% price exploration
    vm.warp(drawOffset + drawLength / 2 - 1 hours);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 49564393939363636337);

    // Half
    vm.warp(drawOffset + drawLength / 2);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 50000000000000000000);

    // End of 1 hour 10% price exploration
    vm.warp(drawOffset + drawLength / 2 + 1 hours);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 50435606060636363635);

    //////////////////////////////////////////////////////////

    // Sixty percent
    vm.warp(drawOffset + (drawLength * 3) / 5);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 51197916666750000001);

    // Three quarters
    vm.warp(drawOffset + (drawLength / 4) * 3);
    amountIn = pair.computeAmountIn(amountOut);
    // NOTE: Slight inaccuracy due to rounding
    assertEq(SD59x18.unwrap(amountIn), 54791666667000000049);

    // Eighty percent
    vm.warp(drawOffset + (drawLength * 4) / 5);
    amountIn = pair.computeAmountIn(amountOut);
    // NOTE: Slight inaccuracy due to rounding
    assertEq(SD59x18.unwrap(amountIn), 57187500000500000003);

    // - 1 second
    vm.warp(drawOffset + drawLength - 1 seconds);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 207045208347736060001002);

    // End
    vm.warp(drawOffset + drawLength);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), uMAX_SD59x18);

    // + 1 second
    vm.warp(drawOffset + drawLength + 1 seconds);
    amountIn = pair.computeAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 0);
  }
}
