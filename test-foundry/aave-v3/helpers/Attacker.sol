// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/core-v3/contracts/interfaces/IPool.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract Attacker {
    using SafeTransferLib for ERC20;

    IPool internal pool;

    constructor(IPool _pool) {
        pool = _pool;
    }

    receive() external payable {}

    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) external {
        ERC20(_token).safeApprove(_spender, _amount);
    }

    function transfer(
        address _token,
        address _recipient,
        uint256 _amount
    ) external {
        ERC20(_token).safeTransfer(_recipient, _amount);
    }

    function deposit(
        address _asset,
        uint256 _amount,
        address _onBehalfOf,
        uint16 _referralCode
    ) external {
        pool.deposit(_asset, _amount, _onBehalfOf, _referralCode);
    }
}