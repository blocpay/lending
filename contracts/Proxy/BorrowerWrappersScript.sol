// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/SafeMath.sol";
import "../Dependencies/blocPayMath.sol";
import "../Dependencies/IERC20.sol";
import "../Interfaces/IBorrowerOperations.sol";
import "../Interfaces/ITroveManager.sol";
import "../Interfaces/IStabilityPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/IBLPYStaking.sol";
import "./BorrowerOperationsScript.sol";
import "./ETHTransferScript.sol";
import "./BLPYStakingScript.sol";
import "../Dependencies/console.sol";


contract BorrowerWrappersScript is BorrowerOperationsScript, ETHTransferScript, BLPYStakingScript {
    using SafeMath for uint;

    string constant public NAME = "BorrowerWrappersScript";

    ITroveManager immutable troveManager;
    IStabilityPool immutable stabilityPool;
    IPriceFeed immutable priceFeed;
    IERC20 immutable USBToken;
    IERC20 immutable BLPYToken;
    IBLPYStaking immutable BLPYStaking;

    constructor(
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _BLPYStakingAddress
    )
        BorrowerOperationsScript(IBorrowerOperations(_borrowerOperationsAddress))
        BLPYStakingScript(_BLPYStakingAddress)
        public
    {
        checkContract(_troveManagerAddress);
        ITroveManager troveManagerCached = ITroveManager(_troveManagerAddress);
        troveManager = troveManagerCached;

        IStabilityPool stabilityPoolCached = troveManagerCached.stabilityPool();
        checkContract(address(stabilityPoolCached));
        stabilityPool = stabilityPoolCached;

        IPriceFeed priceFeedCached = troveManagerCached.priceFeed();
        checkContract(address(priceFeedCached));
        priceFeed = priceFeedCached;

        address USBTokenCached = address(troveManagerCached.USBToken());
        checkContract(USBTokenCached);
        USBToken = IERC20(USBTokenCached);

        address BLPYTokenCached = address(troveManagerCached.BLPYToken());
        checkContract(BLPYTokenCached);
        BLPYToken = IERC20(BLPYTokenCached);

        IBLPYStaking BLPYStakingCached = troveManagerCached.BLPYStaking();
        require(_BLPYStakingAddress == address(BLPYStakingCached), "BorrowerWrappersScript: Wrong BLPYStaking address");
        BLPYStaking = BLPYStakingCached;
    }

    function claimCollateralAndOpenTrove(uint _maxFee, uint _USBAmount, address _upperHint, address _lowerHint) external payable {
        uint balanceBefore = address(this).balance;

        // Claim collateral
        borrowerOperations.claimCollateral();

        uint balanceAfter = address(this).balance;

        // already checked in CollSurplusPool
        assert(balanceAfter > balanceBefore);

        uint totalCollateral = balanceAfter.sub(balanceBefore).add(msg.value);

        // Open trove with obtained collateral, plus collateral sent by user
        borrowerOperations.openTrove{ value: totalCollateral }(_maxFee, _USBAmount, _upperHint, _lowerHint);
    }

    function claimSPRewardsAndRecycle(uint _maxFee, address _upperHint, address _lowerHint) external {
        uint collBalanceBefore = address(this).balance;
        uint BLPYBalanceBefore = BLPYToken.balanceOf(address(this));

        // Claim rewards
        stabilityPool.withdrawFromSP(0);

        uint collBalanceAfter = address(this).balance;
        uint BLPYBalanceAfter = BLPYToken.balanceOf(address(this));
        uint claimedCollateral = collBalanceAfter.sub(collBalanceBefore);

        // Add claimed ETH to trove, get more USB and stake it into the Stability Pool
        if (claimedCollateral > 0) {
            _requireUserHasTrove(address(this));
            uint USBAmount = _getNetUSBAmount(claimedCollateral);
            borrowerOperations.adjustTrove{ value: claimedCollateral }(_maxFee, 0, USBAmount, true, _upperHint, _lowerHint);
            // Provide withdrawn USB to Stability Pool
            if (USBAmount > 0) {
                stabilityPool.provideToSP(USBAmount, address(0));
            }
        }

        // Stake claimed BLPY
        uint claimedBLPY = BLPYBalanceAfter.sub(BLPYBalanceBefore);
        if (claimedBLPY > 0) {
            BLPYStaking.stake(claimedBLPY);
        }
    }

    function claimStakingGainsAndRecycle(uint _maxFee, address _upperHint, address _lowerHint) external {
        uint collBalanceBefore = address(this).balance;
        uint USBBalanceBefore = USBToken.balanceOf(address(this));
        uint BLPYBalanceBefore = BLPYToken.balanceOf(address(this));

        // Claim gains
        BLPYStaking.unstake(0);

        uint gainedCollateral = address(this).balance.sub(collBalanceBefore); // stack too deep issues :'(
        uint gainedUSB = USBToken.balanceOf(address(this)).sub(USBBalanceBefore);

        uint netUSBAmount;
        // Top up trove and get more USB, keeping ICR constant
        if (gainedCollateral > 0) {
            _requireUserHasTrove(address(this));
            netUSBAmount = _getNetUSBAmount(gainedCollateral);
            borrowerOperations.adjustTrove{ value: gainedCollateral }(_maxFee, 0, netUSBAmount, true, _upperHint, _lowerHint);
        }

        uint totalUSB = gainedUSB.add(netUSBAmount);
        if (totalUSB > 0) {
            stabilityPool.provideToSP(totalUSB, address(0));

            // Providing to Stability Pool also triggers BLPY claim, so stake it if any
            uint BLPYBalanceAfter = BLPYToken.balanceOf(address(this));
            uint claimedBLPY = BLPYBalanceAfter.sub(BLPYBalanceBefore);
            if (claimedBLPY > 0) {
                BLPYStaking.stake(claimedBLPY);
            }
        }

    }

    function _getNetUSBAmount(uint _collateral) internal returns (uint) {
        uint price = priceFeed.fetchPrice();
        uint ICR = troveManager.getCurrentICR(address(this), price);

        uint USBAmount = _collateral.mul(price).div(ICR);
        uint borrowingRate = troveManager.getBorrowingRateWithDecay();
        uint netDebt = USBAmount.mul(blocPayMath.DECIMAL_PRECISION).div(blocPayMath.DECIMAL_PRECISION.add(borrowingRate));

        return netDebt;
    }

    function _requireUserHasTrove(address _depositor) internal view {
        require(troveManager.getTroveStatus(_depositor) == 1, "BorrowerWrappersScript: caller must have an active trove");
    }
}
