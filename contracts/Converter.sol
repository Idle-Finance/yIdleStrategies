// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;

import { SafeERC20, SafeMath } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/Uniswap/IUniswapRouter.sol";

import "../interfaces/IConverter.sol";

import "../interfaces/Balancer/IBPool.sol";

contract Converter is IConverter, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public immutable weth;
    address public sushiswap;
    address public idle;
    uint256 public minAmountIn;

    constructor(
        address _sushiswap,
        address _weth,
        address _idle,
        uint256 _minAmountIn
    ) public {
        require(_sushiswap != address(0), "zero-address");
        require(_weth != address(0), "zero-address");
        require(_idle != address(0), "zero-address");

        sushiswap = _sushiswap;
        weth = _weth;
        idle = _idle;
        minAmountIn = _minAmountIn;
    }

    function convert(
        uint256 amountIn,
        uint256 amountOutMin,
        address assetIn,
        address assetOut,
        address to
    ) external override returns (uint256 convertedAmount) {
        require(assetIn != assetOut, "same-asset");

        if (amountIn >= minAmountIn) {
            address _sushiswap = sushiswap;

            IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);
            _ensureAllowance(assetIn, _sushiswap, amountIn);

            uint256[] memory amounts =
                IUniswapRouter(_sushiswap).swapExactTokensForTokens(
                    amountIn,
                    amountOutMin,
                    _getPath(assetIn, assetOut),
                    to,
                    block.timestamp.add(1800)
                );

            convertedAmount = amounts[amounts.length - 1];
        }
    }

    function _ensureAllowance(
        address token,
        address spender,
        uint256 amount
    ) internal {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).safeApprove(spender, 0);
            IERC20(token).safeApprove(spender, type(uint256).max);
        }
    }

    function _getPath(address assetIn, address assetOut) internal view returns (address[] memory path) {
        address _weth = weth;
        if (assetIn == _weth || assetOut == _weth) {
            path = new address[](2);
            path[0] = assetIn;
            path[1] = assetOut;
        } else {
            path = new address[](3);
            path[0] = assetIn;
            path[1] = _weth;
            path[2] = assetOut;
        }
    }

    function getAmountOut(
        uint256 amountIn,
        address assetIn,
        address assetOut
    ) external view override returns (uint256 amountOut) {
        address[] memory path = _getPath(assetIn, assetOut);
        uint256[] memory amounts = IUniswapRouter(sushiswap).getAmountsOut(amountIn, path);
        return amounts[path.length.sub(1)];
    }

    function getAmountIn(
        uint256 amountOut,
        address assetIn,
        address assetOut
    ) external view override returns (uint256 amountIn) {
        address[] memory path = _getPath(assetIn, assetOut);
        uint256[] memory amounts = IUniswapRouter(sushiswap).getAmountsIn(amountIn, path);
        return amounts[0];
    }

    function sweep(address _token) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), IERC20(_token).balanceOf(address(this)));
    }

    function setSushiswap(address _sushiswap) external onlyOwner {
        require(_sushiswap != address(0), "zero-address");
        sushiswap = _sushiswap;
    }

    function setMinAmountIn(uint256 _minAmountIn) external onlyOwner {
        minAmountIn = _minAmountIn;
    }
}
