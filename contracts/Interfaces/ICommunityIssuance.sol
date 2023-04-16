// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

interface ICommunityIssuance { 
    
    // --- Events ---
    
    event BLPYTokenAddressSet(address _BLPYTokenAddress);
    event StabilityPoolAddressSet(address _stabilityPoolAddress);
    event TotalBLPYIssuedUpdated(uint _totalBLPYIssued);

    // --- Functions ---

    function setAddresses(address _BLPYTokenAddress, address _stabilityPoolAddress) external;

    function issueBLPY() external returns (uint);

    function sendBLPY(address _account, uint _BLPYamount) external;
}
