// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

import "./lib/ERC20.sol";

contract StakingWarmup {
    address public immutable staking;
    address public immutable sLotus;

    constructor(address _staking, address _sLotus) {
        require(_staking != address(0));
        staking = _staking;
        require(_sLotus != address(0));
        sLotus = _sLotus;
    }

    function retrieve(address _staker, uint256 _amount) external {
        require(msg.sender == staking);
        IERC20(sLotus).transfer(_staker, _amount);
    }
}
