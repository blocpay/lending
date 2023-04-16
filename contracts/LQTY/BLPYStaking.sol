// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/BaseMath.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";
import "../Interfaces/IBLPYToken.sol";
import "../Interfaces/IBLPYStaking.sol";
import "../Dependencies/blocPayMath.sol";
import "../Interfaces/IUSBToken.sol";

contract BLPYStaking is IBLPYStaking, Ownable, CheckContract, BaseMath {
    using SafeMath for uint;

    // --- Data ---
    string constant public NAME = "BLPYStaking";

    mapping( address => uint) public stakes;
    uint public totalBLPYStaked;

    uint public F_ETH;  // Running sum of ETH fees per-BLPY-staked
    uint public F_USB; // Running sum of BLPY fees per-BLPY-staked

    // User snapshots of F_ETH and F_USB, taken at the point at which their latest deposit was made
    mapping (address => Snapshot) public snapshots; 

    struct Snapshot {
        uint F_ETH_Snapshot;
        uint F_USB_Snapshot;
    }
    
    IBLPYToken public BLPYToken;
    IUSBToken public USBToken;

    address public troveManagerAddress;
    address public borrowerOperationsAddress;
    address public activePoolAddress;

    // --- Events ---

    event BLPYTokenAddressSet(address _BLPYTokenAddress);
    event USBTokenAddressSet(address _USBTokenAddress);
    event TroveManagerAddressSet(address _troveManager);
    event BorrowerOperationsAddressSet(address _borrowerOperationsAddress);
    event ActivePoolAddressSet(address _activePoolAddress);

    event StakeChanged(address indexed staker, uint newStake);
    event StakingGainsWithdrawn(address indexed staker, uint USBGain, uint ETHGain);
    event F_ETHUpdated(uint _F_ETH);
    event F_USBUpdated(uint _F_USB);
    event TotalBLPYStakedUpdated(uint _totalBLPYStaked);
    event EtherSent(address _account, uint _amount);
    event StakerSnapshotsUpdated(address _staker, uint _F_ETH, uint _F_USB);

    // --- Functions ---

    function setAddresses
    (
        address _BLPYTokenAddress,
        address _USBTokenAddress,
        address _troveManagerAddress, 
        address _borrowerOperationsAddress,
        address _activePoolAddress
    ) 
        external 
        onlyOwner 
        override 
    {
        checkContract(_BLPYTokenAddress);
        checkContract(_USBTokenAddress);
        checkContract(_troveManagerAddress);
        checkContract(_borrowerOperationsAddress);
        checkContract(_activePoolAddress);

        BLPYToken = IBLPYToken(_BLPYTokenAddress);
        USBToken = IUSBToken(_USBTokenAddress);
        troveManagerAddress = _troveManagerAddress;
        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePoolAddress = _activePoolAddress;

        emit BLPYTokenAddressSet(_BLPYTokenAddress);
        emit BLPYTokenAddressSet(_USBTokenAddress);
        emit TroveManagerAddressSet(_troveManagerAddress);
        emit BorrowerOperationsAddressSet(_borrowerOperationsAddress);
        emit ActivePoolAddressSet(_activePoolAddress);

        _renounceOwnership();
    }

    // If caller has a pre-existing stake, send any accumulated ETH and USB gains to them. 
    function stake(uint _BLPYamount) external override {
        _requireNonZeroAmount(_BLPYamount);

        uint currentStake = stakes[msg.sender];

        uint ETHGain;
        uint USBGain;
        // Grab any accumulated ETH and USB gains from the current stake
        if (currentStake != 0) {
            ETHGain = _getPendingETHGain(msg.sender);
            USBGain = _getPendingUSBGain(msg.sender);
        }
    
       _updateUserSnapshots(msg.sender);

        uint newStake = currentStake.add(_BLPYamount);

        // Increase user’s stake and total BLPY staked
        stakes[msg.sender] = newStake;
        totalBLPYStaked = totalBLPYStaked.add(_BLPYamount);
        emit TotalBLPYStakedUpdated(totalBLPYStaked);

        // Transfer BLPY from caller to this contract
        BLPYToken.sendToBLPYStaking(msg.sender, _BLPYamount);

        emit StakeChanged(msg.sender, newStake);
        emit StakingGainsWithdrawn(msg.sender, USBGain, ETHGain);

         // Send accumulated USB and ETH gains to the caller
        if (currentStake != 0) {
            USBToken.transfer(msg.sender, USBGain);
            _sendETHGainToUser(ETHGain);
        }
    }

    // Unstake the BLPY and send the it back to the caller, along with their accumulated USB & ETH gains. 
    // If requested amount > stake, send their entire stake.
    function unstake(uint _BLPYamount) external override {
        uint currentStake = stakes[msg.sender];
        _requireUserHasStake(currentStake);

        // Grab any accumulated ETH and USB gains from the current stake
        uint ETHGain = _getPendingETHGain(msg.sender);
        uint USBGain = _getPendingUSBGain(msg.sender);
        
        _updateUserSnapshots(msg.sender);

        if (_BLPYamount > 0) {
            uint BLPYToWithdraw = blocPayMath._min(_BLPYamount, currentStake);

            uint newStake = currentStake.sub(BLPYToWithdraw);

            // Decrease user's stake and total BLPY staked
            stakes[msg.sender] = newStake;
            totalBLPYStaked = totalBLPYStaked.sub(BLPYToWithdraw);
            emit TotalBLPYStakedUpdated(totalBLPYStaked);

            // Transfer unstaked BLPY to user
            BLPYToken.transfer(msg.sender, BLPYToWithdraw);

            emit StakeChanged(msg.sender, newStake);
        }

        emit StakingGainsWithdrawn(msg.sender, USBGain, ETHGain);

        // Send accumulated USB and ETH gains to the caller
        USBToken.transfer(msg.sender, USBGain);
        _sendETHGainToUser(ETHGain);
    }

    // --- Reward-per-unit-staked increase functions. Called by blocPay core contracts ---

    function increaseF_ETH(uint _ETHFee) external override {
        _requireCallerIsTroveManager();
        uint ETHFeePerBLPYStaked;
     
        if (totalBLPYStaked > 0) {ETHFeePerBLPYStaked = _ETHFee.mul(DECIMAL_PRECISION).div(totalBLPYStaked);}

        F_ETH = F_ETH.add(ETHFeePerBLPYStaked); 
        emit F_ETHUpdated(F_ETH);
    }

    function increaseF_USB(uint _USBFee) external override {
        _requireCallerIsBorrowerOperations();
        uint USBFeePerBLPYStaked;
        
        if (totalBLPYStaked > 0) {USBFeePerBLPYStaked = _USBFee.mul(DECIMAL_PRECISION).div(totalBLPYStaked);}
        
        F_USB = F_USB.add(USBFeePerBLPYStaked);
        emit F_USBUpdated(F_USB);
    }

    // --- Pending reward functions ---

    function getPendingETHGain(address _user) external view override returns (uint) {
        return _getPendingETHGain(_user);
    }

    function _getPendingETHGain(address _user) internal view returns (uint) {
        uint F_ETH_Snapshot = snapshots[_user].F_ETH_Snapshot;
        uint ETHGain = stakes[_user].mul(F_ETH.sub(F_ETH_Snapshot)).div(DECIMAL_PRECISION);
        return ETHGain;
    }

    function getPendingUSBGain(address _user) external view override returns (uint) {
        return _getPendingUSBGain(_user);
    }

    function _getPendingUSBGain(address _user) internal view returns (uint) {
        uint F_USB_Snapshot = snapshots[_user].F_USB_Snapshot;
        uint USBGain = stakes[_user].mul(F_USB.sub(F_USB_Snapshot)).div(DECIMAL_PRECISION);
        return USBGain;
    }

    // --- Internal helper functions ---

    function _updateUserSnapshots(address _user) internal {
        snapshots[_user].F_ETH_Snapshot = F_ETH;
        snapshots[_user].F_USB_Snapshot = F_USB;
        emit StakerSnapshotsUpdated(_user, F_ETH, F_USB);
    }

    function _sendETHGainToUser(uint ETHGain) internal {
        emit EtherSent(msg.sender, ETHGain);
        (bool success, ) = msg.sender.call{value: ETHGain}("");
        require(success, "BLPYStaking: Failed to send accumulated ETHGain");
    }

    // --- 'require' functions ---

    function _requireCallerIsTroveManager() internal view {
        require(msg.sender == troveManagerAddress, "BLPYStaking: caller is not TroveM");
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "BLPYStaking: caller is not BorrowerOps");
    }

     function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "BLPYStaking: caller is not ActivePool");
    }

    function _requireUserHasStake(uint currentStake) internal pure {  
        require(currentStake > 0, 'BLPYStaking: User must have a non-zero stake');  
    }

    function _requireNonZeroAmount(uint _amount) internal pure {
        require(_amount > 0, 'BLPYStaking: Amount must be non-zero');
    }

    receive() external payable {
        _requireCallerIsActivePool();
    }
}
