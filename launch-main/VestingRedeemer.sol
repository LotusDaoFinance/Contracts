// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

import "../lib/SafeERC20.sol";
import "../lib/OwnableBase.sol";
import "../lib/SafeMath.sol";
import "./LOTUS.sol";

interface ILotusStaking {
    function stake(uint256 _amount, address _recipient) external returns (bool);

    function unstake(uint256 _amount, bool _trigger) external;

    function claim(address _recipient) external;
}

interface IsLotus {
    function index() external view returns (uint256);
}

// vest Lotus, and the staking contract will stake them
// linear vest, daily unlock
// how to allocate later
contract VestingRedeemer is OwnableBase {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public vestingToken;
    address public stakingContract;
    address public stakingToken;
    LOTUS public lotus;

    event Withdrawal(
        address indexed addr,
        uint256 amountFromInitial,
        uint256 totalAmount
    );

    uint256 public totalAmountWithdrawn;
    uint256 public totalAmountAdded;
    uint256 public totalAmountWithdrawnFromAdded;

    uint256 public startDate;
    uint256 public periodLength;
    uint256 public numberOfPeriods;

    uint256 conversionDenominator = 100;
    uint256 conversionNumerator = 100;

    struct ReceiverInfo {
        uint256 amountWithdrawn;
        uint256 nrtAmountRedeemed;
        uint256 initialNrtAmount;
        bool isRegistered;
    }

    mapping(address => ReceiverInfo) public receiverInfoMap;

    constructor(
        address _vestingToken,
        address _stakingContract,
        address _stakingToken,
        address _nrtaddress,
        uint256 _startDate,
        uint256 _periodLength,
        uint256 _numberOfPeriods
    ) {
        vestingToken = _vestingToken;
        stakingToken = _stakingToken;
        stakingContract = _stakingContract;
        lotus = LOTUS(_nrtaddress);
        startDate = _startDate;
        periodLength = _periodLength;
        numberOfPeriods = _numberOfPeriods;
    }

    function convertLOTUSToLotus(uint256 amount)
        internal
        view
        returns (uint256 LotusAmount)
    {
        LotusAmount = amount.mul(conversionNumerator).div(conversionDenominator);
    }

    function stakeDepositedTokens(uint256 _amount) internal {
        IERC20(vestingToken).approve(stakingContract, _amount);
        ILotusStaking(stakingContract).stake(_amount, address(this));
        ILotusStaking(stakingContract).claim(address(this));
    }

    function unstakeTokens(uint256 _amount) internal {
        IERC20(stakingToken).approve(stakingContract, _amount);
        ILotusStaking(stakingContract).unstake(_amount, true);
    }

    function remainingToWithdraw() public view returns (uint256 amount) {
        uint256 LotusAmount = lotus.balanceOf(msg.sender);
        uint256 LotusAmount = convertLOTUSToLotus(nrtAmount);
        amount = LotusAmount.mul(IsLotus(stakingToken).index()).div(1e9);
    }

    function unstakeAllTokens() internal {
        uint256 amount = IERC20(stakingToken).balanceOf(address(this));
        unstakeTokens(amount);
    }

    function stakeAllTokens() internal {
        uint256 amount = IERC20(vestingToken).balanceOf(address(this));
        stakeDepositedTokens(amount);
    }

    function register(address _addr) internal {
        receiverInfoMap[_addr] = ReceiverInfo({
            amountWithdrawn: 0,
            lotusAmountRedeemed: 0,
            initialLotusAmount: lotus.balanceOf(msg.sender),
            isRegistered: true
        });
    }

    function percentVestedFor() public view returns (uint256 percentVested_) {
        uint256 timeSinceStart = block.timestamp.sub(startDate);

        if (timeSinceStart > 0) {
            percentVested_ = timeSinceStart.mul(10000).div(periodLength).div(
                numberOfPeriods
            );
        } else {
            percentVested_ = 0;
        }
        if (percentVested_ > 10000) percentVested_ = 10000;
    }

    function currentlyClaimable() public view returns (uint256) {
        ReceiverInfo memory userInfo = receiverInfoMap[msg.sender];

        uint256 redeemableAmountTotal = percentVestedFor()
            .mul(userInfo.initialNrtAmount)
            .div(10000);
        if (redeemableAmountTotal < userInfo.nrtAmountRedeemed) {
            return 0;
        }
        return redeemableAmountTotal.sub(userInfo.nrtAmountRedeemed);
    }

    //redeem the launch token with vesting
    function claim() public {
        require(block.timestamp >= startDate, "Redeem not started");
        ReceiverInfo memory userInfo = receiverInfoMap[msg.sender];
        if (!userInfo.isRegistered) {
            register(msg.sender);
            userInfo = receiverInfoMap[msg.sender];
        }
        uint256 timeSinceStart = block.timestamp.sub(startDate);
        uint256 validPeriodCount = timeSinceStart / periodLength;
        if (validPeriodCount > numberOfPeriods) {
            validPeriodCount = numberOfPeriods;
        }
        // userInfo.initialLotusAmount
        uint256 alreadyWithdrawn = userInfo.nrtAmountRedeemed;

        uint256 redeemableAmountFromInitial = percentVestedFor()
            .mul(userInfo.initialLotusAmount)
            .div(10000)
            .sub(alreadyWithdrawn);
        require(
            redeemableAmountFromInitial > 0,
            "vesting: no withdrawable tokens"
        );
        //TODO check 10**9
        uint256 index = IsLotus(stakingToken).index();
        uint256 withdrawableAmount = convertLOTUSToLotus(
            redeemableAmountFromInitial
        ).mul(index).div(10**9);
        // redeem
        nrt.redeem(msg.sender, redeemableAmountFromInitial);
        // transfer token
        unstakeTokens(withdrawableAmount);
        require(IERC20(vestingToken).transfer(msg.sender, withdrawableAmount));

        receiverInfoMap[msg.sender] = ReceiverInfo({
            amountWithdrawn: userInfo.amountWithdrawn.add(withdrawableAmount),
            lotusAmountRedeemed: userInfo.nrtAmountRedeemed.add(
                redeemableAmountFromInitial
            ),
            initialNrtAmount: userInfo.initialNrtAmount,
            isRegistered: true
        });
        totalAmountWithdrawn += withdrawableAmount;
        totalAmountWithdrawnFromAdded += redeemableAmountFromInitial;
        emit Withdrawal(
            msg.sender,
            redeemableAmountFromInitial,
            withdrawableAmount
        );
    }

    // ----------- owner function -----------

    function setStartDate(uint256 _startDate) public onlyOwner {
        require(block.timestamp < startDate, "Vesting already started");
        startDate = _startDate;
    }

    function setPeriodLength(uint256 _length) public onlyOwner {
        require(block.timestamp < startDate, "Vesting already started");
        require(_length > 0, "Need positive length");
        periodLength = _length;
    }

    function setPeriodNumber(uint256 _number) public onlyOwner {
        require(block.timestamp < startDate, "Vesting already started");
        require(_number > 0, "Need positive number of periods");
        numberOfPeriods = _number;
    }

    function setStaking(address _address) public onlyOwner {
        // in case the staking contract changes
        require(_address != address(0));
        unstakeAllTokens();
        stakingContract = _address;
        stakeAllTokens();
    }

    function depositVestingToken(uint256 _amount) public onlyOwner {
        IERC20(vestingToken).transferFrom(msg.sender, address(this), _amount);
        stakeDepositedTokens(_amount);
        totalAmountAdded += _amount;
    }
}
