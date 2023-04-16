// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

interface IBLPYStaking {

    // --- Events --
    
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
    )  external;

    function stake(uint _BLPYamount) external;

    function unstake(uint _BLPYamount) external;

    function increaseF_ETH(uint _ETHFee) external; 

    function increaseF_USB(uint _BLPYFee) external;  

    function getPendingETHGain(address _user) external view returns (uint);

    function getPendingUSDBGain(address _user) external view returns (uint);
}
