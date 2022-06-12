// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;
import "./lib/ERC20.sol";

interface IStaking {
    function stake(uint256 _amount, address _recipient) external returns (bool);

    function claim(address _recipient) external;
}

contract StakingHelper {
    address public immutable staking;
    address public immutable Lotus;

    constructor(address _staking, address _Lotus) {
        require(_staking != address(0));
        staking = _staking;
        require(_Lotus != address(0));
        Lotus = _Lotus;
    }

    function stake(uint256 _amount, address recipient) external {
        IERC20(Lotus).transferFrom(msg.sender, address(this), _amount);
        IERC20(Lotus).approve(staking, _amount);
        IStaking(staking).stake(_amount, recipient);
        IStaking(staking).claim(recipient);
    }
}
