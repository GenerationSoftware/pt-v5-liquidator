// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { SD59x18, convert, MAX_SD59x18 } from "prb-math/SD59x18.sol";

import { ILiquidationSource } from "../src/interfaces/ILiquidationSource.sol";

import { LiquidationPairFactory } from "../src/LiquidationPairFactory.sol";
import { LiquidationPair } from "../src/LiquidationPair.sol";

import { BaseSetup } from "./utils/BaseSetup.sol";

contract LiquidationPairFactoryTest is BaseSetup {
  /* ============ Variables ============ */
  LiquidationPairFactory public factory;
  address public tokenIn;
  address public tokenOut;
  address public source;
  address public target;
  uint32 public periodLength = 1 days;
  uint32 public periodOffset = 1 days;
  SD59x18 public defaultTargetExchangeRate;
  SD59x18 public defaultPhaseTwoRangePercent;
  SD59x18 public defaultPhaseTwoDurationPercent;

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

  /* ============ Set up ============ */

  function setUp() public virtual override {
    super.setUp();
    // Contract setup
    factory = new LiquidationPairFactory(periodLength, periodOffset);
    tokenIn = utils.generateAddress("tokenIn");
    tokenOut = utils.generateAddress("tokenOut");
    source = utils.generateAddress("source");
    target = utils.generateAddress("target");
    defaultTargetExchangeRate = convert(1);
    defaultPhaseTwoRangePercent = convert(10);
    defaultPhaseTwoDurationPercent = convert(20);
  }

  /* ============ External functions ============ */

  /* ============ createPair ============ */

  function testCreatePair() public {
    vm.expectEmit(false, true, true, true);
    emit PairCreated(
      LiquidationPair(0x0000000000000000000000000000000000000000),
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultTargetExchangeRate,
      defaultPhaseTwoDurationPercent,
      defaultPhaseTwoRangePercent
    );

    LiquidationPair pair = factory.createPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultTargetExchangeRate,
      defaultPhaseTwoDurationPercent,
      defaultPhaseTwoRangePercent
    );

    mockTarget(source, target);

    assertEq(address(pair.source()), source);
    assertEq(pair.target(), target);
    assertEq(address(pair.tokenIn()), tokenIn);
    assertEq(address(pair.tokenOut()), tokenOut);
    assertEq(SD59x18.unwrap(pair.targetExchangeRate()), SD59x18.unwrap(defaultTargetExchangeRate));
    assertEq(
      SD59x18.unwrap(pair.phaseTwoRangePercent()),
      SD59x18.unwrap(defaultPhaseTwoRangePercent)
    );
    assertEq(
      SD59x18.unwrap(pair.phaseTwoDurationPercent()),
      SD59x18.unwrap(defaultPhaseTwoDurationPercent)
    );
  }

  /* ============ totalPairs ============ */

  function testTotalPairs() public {
    assertEq(factory.totalPairs(), 0);
    factory.createPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultTargetExchangeRate,
      defaultPhaseTwoDurationPercent,
      defaultPhaseTwoRangePercent
    );
    assertEq(factory.totalPairs(), 1);
  }

  /* ============ Mocks ============ */

  function mockTarget(address _source, address _result) internal {
    vm.mockCall(
      _source,
      abi.encodeWithSelector(ILiquidationSource.targetOf.selector),
      abi.encode(_result)
    );
  }
}
