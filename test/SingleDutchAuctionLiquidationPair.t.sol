// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";
import { SD59x18, convert, uMAX_SD59x18 } from "prb-math/SD59x18.sol";

import { BaseSetup } from "./utils/BaseSetup.sol";
import { LiquidationPair } from "../src/LiquidationPair.sol";
import { Utils } from "./utils/Utils.sol";
import { LiquidatorLib } from "../src/libraries/LiquidatorLib.sol";

contract SingleDutchAuctionLiquidationPair is BaseSetup {
  uint32 public drawLength = 1 days;
  uint32 public drawOffset = 1 days;
  address public tokenIn;
  address public tokenOut;
  address public source;
  address public target;
  SD59x18 public defaultTargetExchangeRate;
  SD59x18 public defaultPhaseTwoRangePercent;
  SD59x18 public defaultPhaseTwoDurationPercent;
  LiquidationPair public pair;

  /* ============ Set up ============ */
  function setUp() public override {
    super.setUp();

    tokenIn = utils.generateAddress("tokenIn");
    tokenOut = utils.generateAddress("tokenOut");
    source = utils.generateAddress("source");
    target = utils.generateAddress("target");

    defaultTargetExchangeRate = convert(1);
    defaultPhaseTwoRangePercent = convert(10);
    defaultPhaseTwoDurationPercent = convert(20);

    // Contract setup
    pair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultTargetExchangeRate,
      defaultPhaseTwoDurationPercent,
      defaultPhaseTwoRangePercent,
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
  function testcomputeExactAmountIn_WithExchangeRate() public {
    SD59x18 amountIn;
    SD59x18 amountOut;
    SD59x18 exchangeRate;

    // 1 IN : 1 OUT
    exchangeRate = convert(1);
    // With .5 OUT -> .5 IN
    amountOut = SD59x18.wrap(50e16);
    amountIn = pair.computeExactAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 50e16);
    // With 1 OUT -> 1 IN
    amountOut = convert(1);
    amountIn = pair.computeExactAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 1e18);
    // With 2 OUT -> 2 IN
    amountOut = convert(2);
    amountIn = pair.computeExactAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 2e18);

    // 1 IN : 2 OUT
    exchangeRate = SD59x18.wrap(50e16);
    // With .5 OUT -> .25 IN
    amountOut = SD59x18.wrap(50e16);
    amountIn = pair.computeExactAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 1e18);
    // With 1 OUT -> .5 IN
    amountOut = convert(1);
    amountIn = pair.computeExactAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 2e18);
    // With 2 OUT -> 1 IN
    amountOut = convert(2);
    amountIn = pair.computeExactAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 4e18);

    // 2 IN : 1 OUT
    exchangeRate = convert(2);
    // With .5 OUT -> 1 IN
    amountOut = SD59x18.wrap(50e16);
    amountIn = pair.computeExactAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 25e16);
    // With 1 OUT -> 2 IN
    amountOut = convert(1);
    amountIn = pair.computeExactAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 50e16);
    // With 2 OUT -> 4 IN
    amountOut = convert(2);
    amountIn = pair.computeExactAmountIn(amountOut, exchangeRate);
    assertEq(SD59x18.unwrap(amountIn), 1e18);
  }

  // Exchange rate is IN per OUT
  function testcomputeExactAmountOut_WithExchangeRate() public {
    SD59x18 amountIn;
    SD59x18 amountOut;
    SD59x18 exchangeRate;

    // 1 IN : 1 OUT
    exchangeRate = convert(1);
    // With .5 IN -> .5 OUT
    amountIn = SD59x18.wrap(50e16);
    amountOut = pair.computeExactAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 50e16);
    // With 1 IN -> 1 OUT
    amountIn = convert(1);
    amountOut = pair.computeExactAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 1e18);
    // With 2 IN -> 2 OUT
    amountIn = convert(2);
    amountOut = pair.computeExactAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 2e18);

    // 1 IN : 2 OUT
    exchangeRate = SD59x18.wrap(50e16);
    // With .5 IN -> 1 OUT
    amountIn = SD59x18.wrap(50e16);
    amountOut = pair.computeExactAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 25e16);
    // With 1 IN -> 2 OUT
    amountIn = convert(1);
    amountOut = pair.computeExactAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 50e16);
    // With 2 IN -> 4 OUT
    amountIn = convert(2);
    amountOut = pair.computeExactAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 1e18);

    // 2 IN : 1 OUT
    exchangeRate = convert(2);
    // With .5 IN -> .25 OUT
    amountIn = SD59x18.wrap(50e16);
    amountOut = pair.computeExactAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 1e18);
    // With 1 IN -> .5 OUT
    amountIn = convert(1);
    amountOut = pair.computeExactAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 2e18);
    // With 2 IN -> 1 OUT
    amountIn = convert(2);
    amountOut = pair.computeExactAmountOut(amountIn, exchangeRate);
    assertEq(SD59x18.unwrap(amountOut), 4e18);
  }

  function testcomputeExactAmountIn_WithTime_DefaultPair_PhaseTransition() public {
    SD59x18 amountIn;
    SD59x18 amountOut = convert(1);

    console2.log("phaseOneEndPercent ", convert(pair.phaseOneEndPercent()));
    console2.log("phaseTwoEndPercent ", convert(pair.phaseTwoEndPercent()));

    uint32 phaseOneEndOffset = uint32(
      uint256(
        convert(convert(int(uint(drawLength))).mul(pair.phaseOneEndPercent()).div(convert(100)))
      )
    );
    uint32 phaseTwoEndOffset = uint32(
      uint256(
        convert(convert(int(uint(drawLength))).mul(pair.phaseTwoEndPercent()).div(convert(100)))
      )
    );

    console.log("phaseOneEndOffset ", phaseOneEndOffset);
    console.log("phaseTwoEndOffset ", phaseTwoEndOffset);

    // At Phase 1 End
    // Should equal target exchange rate - 1/2 of phase 2 range
    vm.warp(drawOffset + phaseOneEndOffset);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 1052631578947368421);

    // At Phase 2 End
    // Should equal target exchange rate + 1/2 of phase 2 range
    vm.warp(drawOffset + phaseTwoEndOffset);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 952380952380952380);
  }

  // With the same amount out -> the amount in decreases over time
  function testcomputeExactAmountIn_WithTime_DefaultPair() public {
    SD59x18 amountIn;
    SD59x18 amountOut = convert(1);

    console2.log("testcomputeExactAmountIn_WithTime_DefaultPair");
    console2.log("phaseOneEndPercent ", convert(pair.phaseOneEndPercent()));
    console2.log("phaseTwoEndPercent ", convert(pair.phaseTwoEndPercent()));

    // - 1 second
    vm.warp(drawOffset - 1 seconds);
    amountIn = pair.computeExactAmountIn(amountOut);
    // NOTE: Any time prior or equal to the drawOffset should return uMAX_SD59x18
    assertEq(SD59x18.unwrap(amountIn), uMAX_SD59x18);

    // Start
    vm.warp(drawOffset);
    amountIn = pair.computeExactAmountIn(amountOut);
    // NOTE: Any time prior or equal to the drawOffset should return uMAX_SD59x18
    assertEq(SD59x18.unwrap(amountIn), uMAX_SD59x18);

    // + 1 second
    vm.warp(drawOffset + 1 seconds);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), uMAX_SD59x18);

    // Twenty percent
    vm.warp(drawOffset + drawLength / 5);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), uMAX_SD59x18);

    // Quarter
    vm.warp(drawOffset + drawLength / 4);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), uMAX_SD59x18);

    // Forty percent
    // NOTE: Slight inaccuracy due to rounding
    vm.warp(drawOffset + (drawLength * 2) / 5);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 1052631578947368421);

    // Half
    vm.warp(drawOffset + drawLength / 2);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), SD59x18.unwrap(defaultTargetExchangeRate));

    // Sixty percent
    // NOTE: Slight inaccuracy due to rounding
    vm.warp(drawOffset + (drawLength * 3) / 5);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 952380952380952380);

    // Three quarters
    vm.warp(drawOffset + (drawLength / 4) * 3);
    amountIn = pair.computeExactAmountIn(amountOut);
    // NOTE: Slight inaccuracy due to rounding
    assertEq(SD59x18.unwrap(amountIn), 246913580246913580);

    // Eighty percent
    vm.warp(drawOffset + (drawLength * 4) / 5);
    amountIn = pair.computeExactAmountIn(amountOut);
    // NOTE: Slight inaccuracy due to rounding
    assertEq(SD59x18.unwrap(amountIn), 165289256198347107);

    // - 1 second
    vm.warp(drawOffset + drawLength - 1 seconds);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 5787169324761);

    // End
    vm.warp(drawOffset + drawLength);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), 0);

    // + 1 second
    vm.warp(drawOffset + drawLength + 1 seconds);
    amountIn = pair.computeExactAmountIn(amountOut);
    assertEq(SD59x18.unwrap(amountIn), uMAX_SD59x18);
  }

  function testcomputeExactAmountOut_WithTime_DefaultPair_PhaseTransition() public {
    SD59x18 amountIn = convert(1);
    SD59x18 amountOut;

    console2.log("phaseOneEndPercent ", convert(pair.phaseOneEndPercent()));
    console2.log("phaseTwoEndPercent ", convert(pair.phaseTwoEndPercent()));

    uint32 phaseOneEndOffset = uint32(
      uint256(
        convert(convert(int(uint(drawLength))).mul(pair.phaseOneEndPercent()).div(convert(100)))
      )
    );
    uint32 phaseTwoEndOffset = uint32(
      uint256(
        convert(convert(int(uint(drawLength))).mul(pair.phaseTwoEndPercent()).div(convert(100)))
      )
    );

    console.log("phaseOneEndOffset ", phaseOneEndOffset);
    console.log("phaseTwoEndOffset ", phaseTwoEndOffset);

    // At Phase 1 End
    // Should equal target exchange rate - 1/2 of phase 2 range
    // NOTE: Slight inaccuracy due to rounding
    vm.warp(drawOffset + phaseOneEndOffset);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(
      SD59x18.unwrap(amountOut),
      SD59x18.unwrap(
        defaultTargetExchangeRate.sub(
          defaultTargetExchangeRate.mul(defaultPhaseTwoRangePercent.div(convert(2))).div(
            convert(100)
          )
        )
      )
    );

    // At Phase 2 End
    // Should equal target exchange rate + 1/2 of phase 2 range
    // NOTE: Slight inaccuracy due to rounding
    vm.warp(drawOffset + phaseTwoEndOffset);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(
      SD59x18.unwrap(amountOut),
      SD59x18.unwrap(
        defaultTargetExchangeRate.add(
          defaultTargetExchangeRate.mul(defaultPhaseTwoRangePercent.div(convert(2))).div(
            convert(100)
          )
        )
      )
    );
  }

  // With the same amount in -> the amount out increases over time
  function testcomputeExactAmountOut_WithTime_DefaultPair() public {
    SD59x18 amountIn = convert(1);
    SD59x18 amountOut;

    console2.log("phaseOneEndPercent ", convert(pair.phaseOneEndPercent()));
    console2.log("phaseTwoEndPercent ", convert(pair.phaseTwoEndPercent()));

    // - 1 second
    vm.warp(drawOffset - 1 seconds);
    amountOut = pair.computeExactAmountOut(amountIn);
    // NOTE: Any time prior or equal to the drawOffset should return 0
    assertEq(SD59x18.unwrap(amountOut), 0);

    // Start
    vm.warp(drawOffset);
    amountOut = pair.computeExactAmountOut(amountIn);
    // NOTE: Any time prior or equal to the drawOffset should return 0
    assertEq(SD59x18.unwrap(amountOut), 0);

    // + 1 second
    vm.warp(drawOffset + 1 seconds);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(SD59x18.unwrap(amountOut), 0);

    // Twenty percent
    vm.warp(drawOffset + drawLength / 5);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(SD59x18.unwrap(amountOut), 0);

    // Quarter
    vm.warp(drawOffset + drawLength / 4);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(SD59x18.unwrap(amountOut), 0);

    // Forty percent
    vm.warp(drawOffset + (drawLength * 2) / 5);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(SD59x18.unwrap(amountOut), 950000000000000000);

    // Half
    vm.warp(drawOffset + drawLength / 2);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(SD59x18.unwrap(amountOut), SD59x18.unwrap(defaultTargetExchangeRate));

    // Sixty percent
    vm.warp(drawOffset + (drawLength * 3) / 5);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(SD59x18.unwrap(amountOut), 1050000000000000000);

    // Three quarters
    vm.warp(drawOffset + (drawLength / 4) * 3);
    amountOut = pair.computeExactAmountOut(amountIn);
    // NOTE: Slight inaccuracy due to rounding
    assertEq(SD59x18.unwrap(amountOut), 4050000000000000000);

    // Eighty percent
    vm.warp(drawOffset + (drawLength * 4) / 5);
    amountOut = pair.computeExactAmountOut(amountIn);
    // NOTE: Slight inaccuracy due to rounding
    assertEq(SD59x18.unwrap(amountOut), 605e16);

    // - 1 second
    vm.warp(drawOffset + drawLength - 1 seconds);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(SD59x18.unwrap(amountOut), 172796050000001105920000);

    // End
    vm.warp(drawOffset + drawLength);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(SD59x18.unwrap(amountOut), uMAX_SD59x18);

    // + 1 second
    vm.warp(drawOffset + drawLength + 1 seconds);
    amountOut = pair.computeExactAmountOut(amountIn);
    assertEq(SD59x18.unwrap(amountOut), 0);
  }
}
