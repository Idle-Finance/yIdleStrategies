// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for the Idle best-yield strategy
/// @notice https://docs.idle.finance/best-yield-documentation/interface
interface IIdleTokenV4 is IERC20 {
    /**
     * @return name
     */
    function name() external view returns (string memory);

    /**
     * @return symbol
     */
    function symbol() external view returns (string memory);

    /**
     * IdleToken price calculation, in underlying
     *
     * @return price in underlying token
     */
    function tokenPrice() external view returns (uint256 price);

    /**
     * @notice IdleToken price for a specific user considering fees, in underlying.
     * this is useful when you need to redeem exactly X underlying
     * @param user address
     * @return priceWFee : IdleToken price with fees
     */
    function tokenPriceWithFee(address user) external view returns (uint256 priceWFee);

    /**
     * @notice Get average price paid for IdleTokens of a user
     * @param user : address of user
     * @return avgPrice : average price paid for IdleTokens
     */
    function userAvgPrices(address user) external view returns (uint256 avgPrice);

    /**
     * @return : underlying token address
     */
    function token() external view returns (address);

    /**
     * Get APR of every ILendingProtocol
     *
     * @return addresses : array of token addresses
     * @return aprs : array of aprs (ordered in respect to the `addresses` array)
     */
    function getAPRs() external view returns (address[] memory addresses, uint256[] memory aprs);

    // external
    // We should save the amount one has deposited to calc interests

    /**
     * Used to mint IdleTokens, given an underlying amount (eg. DAI).
     * This method triggers a rebalance of the pools if needed
     * NOTE: User should 'approve' _amount of tokens before calling mintIdleToken
     * NOTE 2: this method can be paused
     *
     * @param _amount : amount of underlying token to be lended
     * @param _skipRebalance : flag for skipping rebalance for lower gas price
     * @param _referral : referral address
     * @return mintedTokens : amount of IdleTokens minted
     */
    function mintIdleToken(
        uint256 _amount,
        bool _skipRebalance,
        address _referral
    ) external returns (uint256 mintedTokens);

    /**
     * Here we calc the pool share one can withdraw given the amount of IdleToken they want to burn
     * This method triggers a rebalance of the pools if needed
     * NOTE: If the contract is paused or iToken price has decreased one can still redeem but no rebalance happens.
     * NOTE 2: If iToken price has decresed one should not redeem (but can do it) otherwise he would capitalize the loss.
     *         Ideally one should wait until the black swan event is terminated
     *
     * @param _amount : amount of IdleTokens to be burned
     * @return redeemedTokens : amount of underlying tokens redeemed
     */
    function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);

    /**
     * Here we calc the pool share one can withdraw given the amount of IdleToken they want to burn
     * and send interest-bearing tokens (eg. cDAI/iDAI) directly to the user.
     * Underlying (eg. DAI) is not redeemed here.
     *
     * @param _amount : amount of IdleTokens to be burned
     */
    function redeemInterestBearingTokens(uint256 _amount) external;

    /**
     * @return : whether has rebalanced or not
     */
    function rebalance() external returns (bool);
}
