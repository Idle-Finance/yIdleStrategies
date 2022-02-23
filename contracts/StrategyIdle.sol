// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import { BaseStrategyInitializable } from "@yearnvaults/contracts/BaseStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/Idle/IIdleTokenV4.sol";
import "../interfaces/Idle/IdleReservoir.sol";

import "../interfaces/IConverter.sol";

contract StrategyIdle is BaseStrategyInitializable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IIdleTokenV4;
    using Address for address;
    using SafeMath for uint256;

    uint256 private constant MAX_GOV_TOKENS_LENGTH = 5;

    uint256 private constant FULL_ALLOC = 100_000;

    address internal weth;
    address internal converter;
    address public idleReservoir;
    address public idleYieldToken;
    address public referral;

    bool public checkVirtualPrice;
    uint256 public lastVirtualPrice;

    bool public checkRedeemedAmount;

    bool public alreadyRedeemed;

    address[] internal govTokens;

    uint256 public redeemThreshold;

    mapping(address => uint256) minAmountOuts;

    event UpdateGovTokens(address[] _govTokens);
    event UpdateConverter(address _converter);
    event DisableConverter(address _converter);

    modifier updateVirtualPrice() {
        uint256 currentTokenPrice = _getTokenPrice();
        if (checkVirtualPrice) {
            require(
                lastVirtualPrice <= currentTokenPrice,
                "Virtual price is decreasing from the last time, potential losses"
            );
        }
        lastVirtualPrice = currentTokenPrice;
        _;
    }

    modifier onlyGovernanceOrManagement() {
        require(msg.sender == governance() || msg.sender == vault.management(), "!authorized");
        _;
    }

    constructor(
        address _vault,
        address[] memory _govTokens,
        address _weth,
        address _idleReservoir,
        address _idleYieldToken,
        address _referral,
        address _converter
    ) public BaseStrategyInitializable(_vault) {
        _init(_govTokens, _weth, _idleReservoir, _idleYieldToken, _referral, _converter);
    }

    function init(
        address _vault,
        address _onBehalfOf,
        address[] memory _govTokens,
        address _weth,
        address _idleReservoir,
        address _idleYieldToken,
        address _referral,
        address _converter
    ) external {
        super._initialize(_vault, _onBehalfOf, _onBehalfOf, _onBehalfOf);

        _init(_govTokens, _weth, _idleReservoir, _idleYieldToken, _referral, _converter);
    }

    function _init(
        address[] memory _govTokens,
        address _weth,
        address _idleReservoir,
        address _idleYieldToken,
        address _referral,
        address _converter
    ) internal {
        require(
            address(want) == IIdleTokenV4(_idleYieldToken).token(),
            "Vault want is different from Idle token underlying"
        );

        idleReservoir = _idleReservoir;
        idleYieldToken = _idleYieldToken;
        referral = _referral;

        weth = _weth;
        converter = _converter;
        _setGovTokens(_govTokens);

        checkVirtualPrice = true;
        lastVirtualPrice = IIdleTokenV4(_idleYieldToken).tokenPriceWithFee(address(this));

        alreadyRedeemed = false;

        checkRedeemedAmount = true;

        redeemThreshold = 1;

        want.safeApprove(_idleYieldToken, type(uint256).max);
    }

    function setCheckVirtualPrice(bool _checkVirtualPrice) external onlyGovernance {
        checkVirtualPrice = _checkVirtualPrice;
    }

    function setCheckRedeemedAmount(bool _checkRedeemedAmount) external onlyGovernanceOrManagement {
        checkRedeemedAmount = _checkRedeemedAmount;
    }

    function enableAllChecks() external onlyGovernance {
        checkVirtualPrice = true;
        checkRedeemedAmount = true;
    }

    function disableAllChecks() external onlyGovernance {
        checkVirtualPrice = false;
        checkRedeemedAmount = false;
    }

    function setGovTokens(address[] memory _govTokens) external onlyGovernance {
        _setGovTokens(_govTokens);
    }

    function setRedeemThreshold(uint256 _redeemThreshold) external onlyGovernanceOrManagement {
        redeemThreshold = _redeemThreshold;
    }

    function setMinAmountOuts(address[] calldata _tokens, uint256[] calldata _minAmountOuts)
        external
        onlyGovernanceOrManagement
    {
        uint256 length = _tokens.length;
        require(length == _minAmountOuts.length, "not-same-length");

        for (uint256 i; i < length; i++) {
            minAmountOuts[_tokens[i]] = _minAmountOuts[i];
        }
    }

    function setConverter(address _converter) external onlyGovernance {
        address oldConverter = converter;

        address[] memory _govTokens = govTokens;
        uint256 length = _govTokens.length;

        // Disallow old converter and allow new ones
        for (uint256 i; i < length; i++) {
            IERC20 govToken = IERC20(_govTokens[i]);
            govToken.safeApprove(oldConverter, 0);
            govToken.safeApprove(_converter, type(uint256).max);
        }

        // Set new converter
        converter = _converter;

        emit UpdateConverter(_converter);
    }

    function disableConverter() external onlyKeepers {
        address _converter = converter;
        address[] memory _govTokens = govTokens;
        uint256 length = _govTokens.length;
        // Disallow current converter
        for (uint256 i; i < length; i++) {
            IERC20(_govTokens[i]).safeApprove(_converter, 0);
        }

        emit DisableConverter(_converter);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return string(abi.encodePacked("StrategyIdle", IIdleTokenV4(idleYieldToken).symbol()));
    }

    /**
     * @return totalAssets : the value of all positions in terms of `want`
     */
    function estimatedTotalAssets() public view override returns (uint256 totalAssets) {
        IIdleTokenV4 _idleToken = IIdleTokenV4(idleYieldToken);
        uint256 idleTokenBalance = _idleToken.balanceOf(address(this));
        totalAssets = want.balanceOf(address(this));
        if (idleTokenBalance != 0) {
            uint256 balanceInIdle = idleTokenBalance.mul(_idleToken.tokenPriceWithFee(address(this))).div(1e18);
            totalAssets = totalAssets.add(balanceInIdle).add(1);
        }
    }

    /*
     * Perform any strategy unwinding or other calls necessary to capture the "free return"
     * this strategy has generated since the last time it's core position(s) were adjusted.
     * Examples include unwrapping extra rewards. This call is only used during "normal operation"
     * of a Strategy, and should be optimized to minimize losses as much as possible. This method
     * returns any realized profits and/or realized losses incurred, and should return the total
     * amounts of profits/losses/debt payments (in `want` tokens) for the Vault's accounting
     * (e.g. `want.balanceOf(this) >= _debtPayment + _profit - _loss`).
     *
     * NOTE: `_debtPayment` should be less than or equal to `_debtOutstanding`. It is okay for it
     *       to be less than `_debtOutstanding`, as that should only used as a guide for how much
     *       is left to pay back. Payments should be made to minimize loss from slippage, debt,
     *       withdrawal fees, etc.
     */
    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // Reset, it could have been set during a withdrawal
        if (alreadyRedeemed) {
            alreadyRedeemed = false;
        }

        // Assure IdleController has IDLE tokens during redeem
        IdleReservoir(idleReservoir).drip();

        IERC20 _want = want;
        // Get debt, currentValue (want+idle), only want
        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 currentValue = estimatedTotalAssets();
        uint256 wantBalance = _balanceOfWant(_want);

        // Calculate total profit w/o farming
        if (debt < currentValue) {
            _profit = currentValue.sub(debt);
        } else {
            _loss = debt.sub(currentValue);
        }

        // To withdraw = profit from lending + _debtOutstanding
        uint256 toFree = _debtOutstanding.add(_profit);

        // In the case want is not enough, divest from idle

        if (toFree > wantBalance) {
            // Divest only the missing part = toFree-wantBalance
            toFree = toFree.sub(wantBalance);
            uint256 freedAmount = freeAmount(toFree);

            // loss in the case freedAmount less to be freed
            uint256 withdrawalLoss = freedAmount < toFree ? toFree.sub(freedAmount) : 0;

            // profit recalc
            if (withdrawalLoss < _profit) {
                _profit = _profit.sub(withdrawalLoss);
            } else {
                _loss = _loss.add(withdrawalLoss.sub(_profit));
                _profit = 0;
            }
        }

        // Claim only if not done in the previous liquidate step during redeem
        if (!alreadyRedeemed) {
            IIdleTokenV4(idleYieldToken).redeemIdleToken(0);
        } else {
            alreadyRedeemed = false;
        }

        // If we have govTokens, let's convert them!
        // This is done in a separate step since there might have been
        // a migration or an exitPosition
        uint256 liquidated = _liquidateGovTokens();

        // Increase profit by liquidated amount
        _profit = _profit.add(liquidated);

        // Recalculate profit
        wantBalance = _balanceOfWant(_want);

        if (wantBalance < _profit) {
            _profit = wantBalance;
            _debtPayment = 0;
        } else if (wantBalance < _debtOutstanding.add(_profit)) {
            _debtPayment = wantBalance.sub(_profit);
        } else {
            _debtPayment = _debtOutstanding;
        }
    }

    /*
     * Perform any adjustments to the core position(s) of this strategy given
     * what change the Vault made in the "investable capital" available to the
     * strategy. Note that all "free capital" in the strategy after the report
     * was made is available for reinvestment. Also note that this number could
     * be 0, and you should handle that scenario accordingly.
     */
    function adjustPosition(uint256 _debtOutstanding) internal override updateVirtualPrice {
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)

        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        uint256 balanceOfWant = _balanceOfWant(want);
        if (balanceOfWant > _debtOutstanding) {
            IIdleTokenV4(idleYieldToken).mintIdleToken(balanceOfWant.sub(_debtOutstanding), true, referral);
        }
    }

    /*
     * Safely free an amount from Idle protocol
     */
    function freeAmount(uint256 _amount) internal updateVirtualPrice returns (uint256 freedAmount) {
        IIdleTokenV4 _idleYieldToken = IIdleTokenV4(idleYieldToken);
        IERC20 _want = want;

        uint256 valueToRedeemApprox = _amount.mul(1e18).div(lastVirtualPrice).add(1);
        uint256 valueToRedeem = Math.min(valueToRedeemApprox, _idleYieldToken.balanceOf(address(this)));

        alreadyRedeemed = true;

        uint256 preBalanceOfWant = _balanceOfWant(_want);
        _idleYieldToken.redeemIdleToken(valueToRedeem);
        freedAmount = _balanceOfWant(_want).sub(preBalanceOfWant);

        if (checkRedeemedAmount) {
            // Note: could be equal, prefer >= in case of rounding
            // We just need that is at least the amountToRedeem, not below
            require(freedAmount.add(redeemThreshold) >= _amount, "Redeemed amount must be >= amountToRedeem");
        }
    }

    /*
     * Liquidate as many assets as possible to `want`, irregardless of slippage,
     * up to `_amountNeeded`. Any excess should be re-invested here as well.
     */
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        updateVirtualPrice
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        IERC20 _want = want;
        uint256 wantBalance = _balanceOfWant(_want);

        if (wantBalance < _amountNeeded) {
            // Note: potential drift by 1 wei, reduce to max balance in the case approx is rounded up
            uint256 amountToRedeem = _amountNeeded.sub(wantBalance);
            freeAmount(amountToRedeem);
            wantBalance = _balanceOfWant(_want);
        }

        // _liquidatedAmount min(_amountNeeded, balanceOfWant), otw vault accounting breaks
        if (wantBalance >= _amountNeeded) {
            _liquidatedAmount = _amountNeeded;
        } else {
            _liquidatedAmount = wantBalance;
            _loss = _amountNeeded.sub(wantBalance);
        }
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function harvestTrigger(uint256 callCost) public view override returns (bool) {
        return super.harvestTrigger(ethToWant(callCost));
    }

    function prepareMigration(address _newStrategy) internal override {
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one

        // this automatically claims the gov tokens in addition to want
        IIdleTokenV4 _idleToken = IIdleTokenV4(idleYieldToken);
        _idleToken.redeemIdleToken(_idleToken.balanceOf(address(this)));

        // Transfer gov tokens to new strategy
        address[] memory _govTokens = govTokens;
        uint256 length = _govTokens.length;
        IERC20 govToken;
        for (uint256 i = 0; i < length; i++) {
            govToken = IERC20(_govTokens[i]);
            govToken.safeTransfer(_newStrategy, govToken.balanceOf(address(this)));
        }
    }

    /**
     * Liquidate everything and returns the amount that got freed.
     * This function is used during emergency exit instead of `prepareReturn()` to
     * liquidate all of the Strategy's positions back to the Vault.
     */

    function liquidateAllPositions() internal override returns (uint256 _amountFreed) {
        IIdleTokenV4 _idleYieldToken = IIdleTokenV4(idleYieldToken);
        _idleYieldToken.redeemIdleToken(_idleYieldToken.balanceOf(address(this)));

        _amountFreed = _balanceOfWant(want);
    }

    function protectedTokens() internal view override returns (address[] memory) {
        address[] memory _govTokens = govTokens;
        uint256 length = _govTokens.length;
        address[] memory protected = new address[](1 + length);

        for (uint256 i; i < length; i++) {
            protected[i] = _govTokens[i];
        }
        protected[_govTokens.length] = idleYieldToken;

        return protected;
    }

    function balanceOfWant() external view returns (uint256) {
        return _balanceOfWant(want);
    }

    function _balanceOfWant(IERC20 _want) internal view returns (uint256) {
        return _want.balanceOf(address(this));
    }

    function ethToWant(uint256 _amount) public view override returns (uint256) {
        if (_amount == 0) {
            return 0;
        }

        return IConverter(converter).getAmountOut(_amount, weth, address(want));
    }

    function getTokenPrice() public view returns (uint256) {
        return _getTokenPrice();
    }

    function _liquidateGovTokens() internal returns (uint256 liquidated) {
        IConverter _converter = IConverter(converter);
        address _wantAddress = address(want);

        address[] memory _govTokens = govTokens;
        uint256 length = _govTokens.length;

        for (uint256 i; i < _govTokens.length; i++) {
            address govTokenAddress = _govTokens[i];
            uint256 balance = IERC20(govTokenAddress).balanceOf(address(this));
            if (balance > 0) {
                uint256 convertedAmount = _converter.convert(
                    balance,
                    minAmountOuts[govTokenAddress],
                    govTokenAddress,
                    _wantAddress,
                    address(this)
                );

                // leverage uniswap returns want amount
                liquidated = liquidated.add(convertedAmount);
            }
        }
    }

    function _setGovTokens(address[] memory _govTokens) internal {
        require(_govTokens.length <= MAX_GOV_TOKENS_LENGTH, "GovTokens too long");

        address _converter = converter;

        // Disallow uniswap on old tokens
        address[] memory oldGovTokens = govTokens;
        uint256 length = oldGovTokens.length;
        for (uint256 i; i < length; i++) {
            address govTokenAddress = oldGovTokens[i];
            IERC20(govTokenAddress).safeApprove(_converter, 0);
        }

        // Set new gov tokens
        govTokens = _govTokens;

        // Allow uniswap on new tokens
        length = _govTokens.length;
        for (uint256 i; i < length; i++) {
            address govTokenAddress = _govTokens[i];
            IERC20(govTokenAddress).safeApprove(_converter, type(uint256).max);
        }

        emit UpdateGovTokens(_govTokens);
    }

    function getConverter() external view returns (address) {
        return converter;
    }

    function getGovTokens() external view returns (address[] memory) {
        return govTokens;
    }

    function getWeth() external view returns (address) {
        return weth;
    }

    function _getTokenPrice() internal view returns (uint256) {
        return IIdleTokenV4(idleYieldToken).tokenPriceWithFee(address(this));
    }
}
