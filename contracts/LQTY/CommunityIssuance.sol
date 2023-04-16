// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Interfaces/IBLPYToken.sol";
import "../Interfaces/ICommunityIssuance.sol";
import "../Dependencies/BaseMath.sol";
import "../Dependencies/blocPayMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/SafeMath.sol";


contract CommunityIssuance is ICommunityIssuance, Ownable, CheckContract, BaseMath {
    using SafeMath for uint;

    // --- Data ---

    string constant public NAME = "CommunityIssuance";

    uint constant public SECONDS_IN_ONE_MINUTE = 60;

   /* The issuance factor F determines the curvature of the issuance curve.
    *
    * Minutes in one year: 60*24*365 = 525600
    *
    * For 50% of remaining tokens issued each year, with minutes as time units, we have:
    * 
    * F ** 525600 = 0.5
    * 
    * Re-arranging:
    * 
    * 525600 * ln(F) = ln(0.5)
    * F = 0.5 ** (1/525600)
    * F = 0.999998681227695000 
    */
    uint constant public ISSUANCE_FACTOR = 999998681227695000;

    /* 
    * The community BLPY supply cap is the starting balance of the Community Issuance contract.
    * It should be minted to this contract by BLPYToken, when the token is deployed.
    * 
    * Set to 32M (slightly less than 1/3) of total BLPY supply.
    */
    uint constant public BLPYSupplyCap = 32e24; // 32 million

    IBLPYToken public BLPYToken;

    address public stabilityPoolAddress;

    uint public totalBLPYIssued;
    uint public immutable deploymentTime;

    // --- Events ---

    event BLPYTokenAddressSet(address _BLPYTokenAddress);
    event StabilityPoolAddressSet(address _stabilityPoolAddress);
    event TotalBLPYIssuedUpdated(uint _totalBLPYIssued);

    // --- Functions ---

    constructor() public {
        deploymentTime = block.timestamp;
    }

    function setAddresses
    (
        address _BLPYTokenAddress, 
        address _stabilityPoolAddress
    ) 
        external 
        onlyOwner 
        override 
    {
        checkContract(_BLPYTokenAddress);
        checkContract(_stabilityPoolAddress);

        BLPYToken = IBLPYToken(_BLPYTokenAddress);
        stabilityPoolAddress = _stabilityPoolAddress;

        // When BLPYToken deployed, it should have transferred CommunityIssuance's BLPY entitlement
        uint BLPYBalance = BLPYToken.balanceOf(address(this));
        assert(BLPYBalance >= BLPYSupplyCap);

        emit BLPYTokenAddressSet(_BLPYTokenAddress);
        emit StabilityPoolAddressSet(_stabilityPoolAddress);

        _renounceOwnership();
    }

    function issueBLPY() external override returns (uint) {
        _requireCallerIsStabilityPool();

        uint latestTotalBLPYIssued = BLPYSupplyCap.mul(_getCumulativeIssuanceFraction()).div(DECIMAL_PRECISION);
        uint issuance = latestTotalBLPYIssued.sub(totalBLPYIssued);

        totalBLPYIssued = latestTotalBLPYIssued;
        emit TotalBLPYIssuedUpdated(latestTotalBLPYIssued);
        
        return issuance;
    }

    /* Gets 1-f^t    where: f < 1

    f: issuance factor that determines the shape of the curve
    t:  time passed since last BLPY issuance event  */
    function _getCumulativeIssuanceFraction() internal view returns (uint) {
        // Get the time passed since deployment
        uint timePassedInMinutes = block.timestamp.sub(deploymentTime).div(SECONDS_IN_ONE_MINUTE);

        // f^t
        uint power = blocPayMath._decPow(ISSUANCE_FACTOR, timePassedInMinutes);

        //  (1 - f^t)
        uint cumulativeIssuanceFraction = (uint(DECIMAL_PRECISION).sub(power));
        assert(cumulativeIssuanceFraction <= DECIMAL_PRECISION); // must be in range [0,1]

        return cumulativeIssuanceFraction;
    }

    function sendBLPY(address _account, uint _BLPYamount) external override {
        _requireCallerIsStabilityPool();

        BLPYToken.transfer(_account, _BLPYamount);
    }

    // --- 'require' functions ---

    function _requireCallerIsStabilityPool() internal view {
        require(msg.sender == stabilityPoolAddress, "CommunityIssuance: caller is not SP");
    }
}
