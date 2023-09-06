// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";
import "./Heap.sol";

/// @custom:repo https://github.com/eliphang/spicy-combos-contracts
contract SpicyCombos is Ownable {
    enum HelpingType {
        DoubleHelping,
        TimedHelping
    }

    struct Queue {
        HeapData queue;
        mapping(address => Helping) helpings;
    }

    struct Helping {
        address owner;
        HelpingType helpingType;
        bool usingCredit; // Is this using a credit or a deposit?
    }

    struct Balance {
        uint256 deposits;
        uint256 credits;
    }

    uint256 public totalDeposits = 0;

    /// The minimum cost of a helping. All combo costs will be a multiple of this.
    uint256 public immutable minValue;

    mapping(uint256 => Queue) queues; // The keys are comboIds
    mapping(address => Balance) public balances;

    error ValueOutOfRange(
        string parameter,
        uint256 allowedMinimum,
        uint256 allowedMaximum
    );
    error NotEnoughCredits(uint256 credits, uint256 comboPrice);
    error NotEnoughDeposits(uint256 deposits, uint256 comboPrice);
    error NotEnoughDepositsForPremium(uint256 deposits, uint256 premium);

    modifier comboValuesInRange(
        uint256 amountDigit1,
        uint256 amountDigit2,
        uint256 amountZeros,
        uint256 blocksDigit1,
        uint256 blocksDigit2,
        uint256 blocksZeros
    ) {
        if (amountDigit1 == 0 || amountDigit1 > 9) {
            revert ValueOutOfRange("amountDigit1", 1, 9);
        }
        if (amountDigit2 > 9) {
            revert ValueOutOfRange("amountDigit2", 0, 9);
        }
        if (amountZeros > 9) {
            revert ValueOutOfRange("amountZeros", 0, 9);
        }
        if (blocksDigit1 == 0 || blocksDigit1 > 9) {
            revert ValueOutOfRange("blocksDigit1", 1, 9);
        }
        if (blocksDigit2 > 9) {
            revert ValueOutOfRange("blocksDigit2", 0, 9);
        }
        if (blocksZeros > 6) {
            revert ValueOutOfRange("blocksZeros", 0, 6);
        }
        _;
    }

    /// @param minValue_ the minimum value that can be deposited.
    constructor(uint256 minValue_) {
        minValue = minValue_;
    }

    receive() external payable {
        balances[msg.sender].deposits += msg.value;
    }

    /// Withdraw all funds set aside for the dev fund.
    /// @dev The contract "owner" is considered the destination address of the dev fund.
    /// @dev The owner has no other privilege than to receive the amount set aside in the dev fund.
    function withdrawDevFund() external {
        uint256 balance = address(this).balance;
        uint256 devFund = balance - totalDeposits;
        uint256 tempDeposits = totalDeposits;
        // Temporarily set `totalDeposits` to the entire smart contract balance to disallow the devFund to use reentrancy to withdraw more than its share.
        totalDeposits = balance;
        owner().call{value: devFund}(""); // the devFund might be a smart contract, so forward all gas
        // Set `totalDeposits` back to what it was.
        totalDeposits = tempDeposits;
    }

    /// Get a helping. The first six parameters uniquely define a spicy combo.
    /// @param amountDigit1 first significant digit in the amount.
    /// @param amountDigit2 second significant digit in the amount (or zero if there is only one significant digit).
    /// @param amountZeros number of zeros to add to the minimum value for amount.
    /// @param blocksDigit1 first significant digit in the number of blocks for timed helpings.
    /// @param blocksDigit2 second significant digit in the number of blocks (or zero if there is only one significant digit).
    /// @param blocksZeros number of zeros to add to the number of blocks.
    /// @param doubleHelping Is this a double helping? If not, it's a timed helping.
    /// @param premium the amount paid to advance in the queue. This can only come from deposits, not credits.
    function addHelping(
        uint256 amountDigit1,
        uint256 amountDigit2,
        uint256 amountZeros,
        uint256 blocksDigit1,
        uint256 blocksDigit2,
        uint256 blocksZeros,
        bool doubleHelping,
        bool useCredits,
        uint256 premium
    )
        external
        payable
        comboValuesInRange(
            amountDigit1,
            amountDigit2,
            amountZeros,
            blocksDigit1,
            blocksDigit2,
            blocksZeros
        )
    {
        HelpingType helpingType;
        if (doubleHelping) {
            helpingType = HelpingType.DoubleHelping;
        } else {
            helpingType = HelpingType.TimedHelping;
        }

        Balance storage balance = balances[msg.sender];
        balance.deposits += msg.value;

        if (balance.deposits < premium) {
            revert NotEnoughDepositsForPremium(balance.deposits, premium);
        }

        unchecked {
            balance.deposits -= premium; // premiums go to the dev fund
        }

        uint256 comboId = computeComboId(
            amountDigit1,
            amountDigit2,
            amountZeros,
            blocksDigit1,
            blocksDigit2,
            blocksZeros
        );
        uint256 comboPrice = computeValue(
            amountDigit1,
            amountDigit2,
            amountZeros
        );

        if (useCredits) {
            if (balance.credits < comboPrice) {
                revert NotEnoughCredits(balance.credits, comboPrice);
            }
            balance.credits -= comboPrice;
        } else {
            // use deposits
            if (balance.deposits < comboPrice) {
                revert NotEnoughDeposits(balance.deposits, comboPrice);
            }
            balance.deposits -= comboPrice;
            transferRewardToFirstInQueue(comboId);
        }
        updateQueue(comboId, helpingType, useCredits, premium);
    }

    function deposit() external payable {
        balances[msg.sender].deposits += msg.value;
    }

    function withdraw() external {}

    /// Get a queue's size and max value from the six values uniquely identifying a combo.
    function queueSizeAndMaxValue(
        uint256 amountDigit1,
        uint256 amountDigit2,
        uint256 amountZeros,
        uint256 blocksDigit1,
        uint256 blocksDigit2,
        uint256 blocksZeros
    )
        external
        view
        comboValuesInRange(
            amountDigit1,
            amountDigit2,
            amountZeros,
            blocksDigit1,
            blocksDigit2,
            blocksZeros
        )
    {
        uint256 comboId = computeComboId(
            amountDigit1,
            amountDigit2,
            amountZeros,
            blocksDigit1,
            blocksDigit2,
            blocksZeros
        );
    }

    function computeComboId(
        uint256 amountDigit1,
        uint256 amountDigit2,
        uint256 amountZeros,
        uint256 blocksDigit1,
        uint256 blocksDigit2,
        uint256 blocksZeros
    ) public pure returns (uint256) {
        return
            blocksZeros +
            blocksDigit2 *
            10 +
            blocksDigit1 *
            100 +
            amountZeros *
            1000 +
            amountDigit2 *
            10000 +
            amountDigit1 *
            100000;
    }

    function computeValue(
        uint256 digit1,
        uint256 digit2,
        uint256 zeros
    ) public pure returns (uint256) {
        if (digit2 == 0) {
            // only one significant digit
            return digit1 * 10**zeros;
        }
        return (digit1 * 10 + digit2) * 10**zeros;
    }

    function transferRewardToFirstInQueue(uint256 comboId) internal {}

    function updateQueue(
        uint256 comboId,
        HelpingType helpingType,
        bool useCredits,
        uint256 premium
    ) internal {}
}
