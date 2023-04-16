// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/CheckContract.sol";
import "../Interfaces/IBLPYStaking.sol";


contract BLPYStakingScript is CheckContract {
    IBLPYStaking immutable BLPYStaking;

    constructor(address _BLPYStakingAddress) public {
        checkContract(_BLPYStakingAddress);
        BLPYStaking = IBLPYStaking(_BLPYStakingAddress);
    }

    function stake(uint _BLPYamount) external {
        BLPYStaking.stake(_BLPYamount);
    }
}
