// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract SpicyCombos is Ownable {
    uint devFund = 0;

    /// Withdraw all funds set aside for the dev fund.
    /// @dev The contract "owner" is considered the destination address of the dev fund.
    /// @dev The owner has no other privilege than to receive the amount set aside in the dev fund.
    function withdrawDevFund() external {
        uint amount = devFund;
        devFund = 0; // don't allow the devFund to use reentrancy to withdraw more than its share
        owner().call{value: amount}(""); // the devFund might be a smart contract, so forward all gas 
    }
}