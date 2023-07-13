// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { SD59x18, convert, MAX_SD59x18 } from "prb-math/SD59x18.sol";

import { LiquidationPairFactory } from "../src/LiquidationPairFactory.sol";
import { LiquidationPair } from "../src/LiquidationPair.sol";
import { LiquidationRouter } from "../src/LiquidationRouter.sol";

import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";

import { LiquidatorLib } from "../src/libraries/LiquidatorLib.sol";

import { BaseSetup } from "./utils/BaseSetup.sol";

contract LiquidationRouterTest is BaseSetup {
  using SafeERC20 for IERC20;

  /* ============ Events ============ */

  event LiquidationRouterCreated(LiquidationPairFactory indexed liquidationPairFactory);

  /* ============ Variables ============ */

  address public defaultReceiver;

  LiquidationPairFactory public factory;
  LiquidationRouter public liquidationRouter;
  LiquidationPair public pair;

  address public tokenIn;
  address public tokenOut;
  address public source;
  address public defaultTarget;
  uint32 public periodLength = 1 days;
  uint32 public periodOffset = 1 days;
  SD59x18 public defaultTargetExchangeRate;
  SD59x18 public defaultPhaseTwoRangePercent;
  SD59x18 public defaultPhaseTwoDurationPercent;

  /* ============ Set up ============ */

  function setUp() public virtual override {
    super.setUp();

    defaultReceiver = bob;
    defaultTarget = carol;

    tokenIn = utils.generateAddress("tokenIn");
    tokenOut = utils.generateAddress("tokenOut");
    defaultTargetExchangeRate = convert(1);
    defaultPhaseTwoRangePercent = convert(10);
    defaultPhaseTwoDurationPercent = convert(20);

    source = utils.generateAddress("source");

    factory = new LiquidationPairFactory(periodLength, periodOffset);
    liquidationRouter = new LiquidationRouter(factory);
    pair = factory.createPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultTargetExchangeRate,
      defaultPhaseTwoRangePercent,
      defaultPhaseTwoDurationPercent
    );
  }

  /* ============ Constructor ============ */

  function testConstructor() public {
    vm.expectEmit(true, false, false, true);
    emit LiquidationRouterCreated(factory);

    new LiquidationRouter(factory);
  }

  /* ============ swapExactAmountIn ============ */

  function testSwapExactAmountIn_HappyPath() public {
    mockSwapIn(
      address(factory),
      address(pair),
      tokenIn,
      alice,
      defaultReceiver,
      defaultTarget,
      1e18,
      1e18,
      1e18
    );

    vm.prank(alice);
    liquidationRouter.swapExactAmountIn(pair, defaultReceiver, 1e18, 1e18);
  }

  /* ============ swapExactAmountOut ============ */

  function testSwapExactAmountOut_HappyPath() public {
    mockSwapOut(
      address(factory),
      address(pair),
      tokenIn,
      alice,
      defaultReceiver,
      defaultTarget,
      1e18,
      1e18,
      1e18
    );

    vm.prank(alice);
    liquidationRouter.swapExactAmountOut(pair, defaultReceiver, 1e18, 1e18);
  }

  /* ============ Mocks ============ */

  function mockTokenIn(address _liquidationPair, address _result) internal {
    vm.mockCall(_liquidationPair, abi.encodeWithSignature("tokenIn()"), abi.encode(_result));
  }

  function mockTarget(address _liquidationPair, address _result) internal {
    vm.mockCall(
      _liquidationPair,
      abi.encodeWithSelector(LiquidationPair.target.selector),
      abi.encode(_result)
    );
  }

  function mockComputeExactAmountIn(
    address _liquidationPair,
    uint256 _amountOut,
    uint256 _result
  ) internal {
    vm.mockCall(
      _liquidationPair,
      abi.encodeWithSignature("computeExactAmountIn(uint256)", _amountOut),
      abi.encode(_result)
    );
  }

  function mockComputeExactAmountOut(
    address _liquidationPair,
    uint256 _amountIn,
    uint256 _result
  ) internal {
    vm.mockCall(
      _liquidationPair,
      abi.encodeWithSignature("computeExactAmountOut(uint256)", _amountIn),
      abi.encode(_result)
    );
  }

  function mockDeployedPairs(address _factory, address _liquidationPair, bool _result) internal {
    vm.mockCall(
      _factory,
      abi.encodeWithSignature("deployedPairs(address)", _liquidationPair),
      abi.encode(_result)
    );
  }

  // NOTE: Function selector of safeTransferFrom wasn't working
  function mockTransferFrom(address _token, address _from, address _to, uint256 _amount) internal {
    vm.mockCall(
      _token,
      abi.encodeWithSignature("transferFrom(address,address,uint256)", _from, _to, _amount),
      abi.encode()
    );
  }

  function mockSwapExactAmountIn(
    address _liquidationPair,
    address _receiver,
    uint256 _amountIn,
    uint256 _amountOutMin,
    uint256 _result
  ) internal {
    vm.mockCall(
      _liquidationPair,
      abi.encodeWithSignature(
        "swapExactAmountIn(address,uint256,uint256)",
        _receiver,
        _amountIn,
        _amountOutMin
      ),
      abi.encode(_result)
    );
  }

  function mockSwapExactAmountOut(
    address _liquidationPair,
    address _receiver,
    uint256 _amountOut,
    uint256 _amountInMax,
    uint256 _result
  ) internal {
    vm.mockCall(
      _liquidationPair,
      abi.encodeWithSignature(
        "swapExactAmountOut(address,uint256,uint256)",
        _receiver,
        _amountOut,
        _amountInMax
      ),
      abi.encode(_result)
    );
  }

  function mockSwapIn(
    address _factory,
    address _liquidationPair,
    address _tokenIn,
    address _sender,
    address _receiver,
    address _target,
    uint256 _amountIn,
    uint256 _amountOutMin,
    uint256 _result
  ) internal {
    mockDeployedPairs(_factory, _liquidationPair, true);
    mockTokenIn(_liquidationPair, _tokenIn);
    mockTarget(_liquidationPair, _target);
    mockTransferFrom(_tokenIn, _sender, _target, _amountIn);
    mockSwapExactAmountIn(_liquidationPair, _receiver, _amountIn, _amountOutMin, _result);
  }

  function mockSwapOut(
    address _factory,
    address _liquidationPair,
    address _tokenIn,
    address _sender,
    address _receiver,
    address _target,
    uint256 _amountOut,
    uint256 _amountInMax,
    uint256 _result
  ) internal {
    mockDeployedPairs(_factory, _liquidationPair, true);
    mockTokenIn(_liquidationPair, _tokenIn);
    mockTarget(_liquidationPair, _target);
    mockComputeExactAmountIn(_liquidationPair, _amountOut, _result);
    mockTransferFrom(_tokenIn, _sender, _target, _result);
    mockSwapExactAmountOut(_liquidationPair, _receiver, _amountOut, _amountInMax, _result);
  }
}
