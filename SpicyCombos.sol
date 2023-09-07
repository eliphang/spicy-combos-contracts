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
        HeapData heapData; // contains all helpings after the active one
        mapping(address => Helping) helpings;
        Helping activeHelping;
    }

    struct Helping {
        address owner;
        HelpingType helpingType;
        uint256 startBlock; // used by HelpingType.TimedHelping
        uint256 depositsReceived; // deposits received while this was the active helping
        bool exists;
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

    error ValueOutOfRange(string parameter, uint256 allowedMinimum, uint256 allowedMaximum);
    error NotEnoughCredits(uint256 credits, uint256 comboPrice);
    error NotEnoughDeposits(uint256 deposits, uint256 comboPrice);
    error NotEnoughDepositsForPremium(uint256 deposits, uint256 premium);
    error FirstOnlyIncompatibleWithUseCredits();
    error FirstOnlyUnsuccessful();

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
    /// @param useCredits Use credits instead of deposits for the base combo price (not including premium).
    /// @param premium the amount paid to advance in the queue. This can only come from deposits, not credits.
    /// @param firstOnly Use this if you want to have a first place bonus and fail (revert) if you don't get it.
    function addHelping(
        uint256 amountDigit1,
        uint256 amountDigit2,
        uint256 amountZeros,
        uint256 blocksDigit1,
        uint256 blocksDigit2,
        uint256 blocksZeros,
        bool doubleHelping,
        bool useCredits,
        bool firstOnly,
        uint256 premium
    )
        external
        payable
        comboValuesInRange(amountDigit1, amountDigit2, amountZeros, blocksDigit1, blocksDigit2, blocksZeros)
    {
        Balance storage balance = balances[msg.sender];
        // Make sure addHelping() never calls an outside function or there could be a reentrancy attack.
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
        uint256 comboPrice = computeValue(amountDigit1, amountDigit2, amountZeros);

        Queue storage queue = queues[comboId];
        bool queueEmpty = Heap.size(queue.heapData) == 0;

        if (useCredits) {
            if (firstOnly) {
                revert FirstOnlyIncompatibleWithUseCredits();
            }
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
        }

        // Update Queue
        uint256 timeLimit = computeValue(blocksDigit1, blocksDigit2, blocksZeros);
        removeActiveHelpingIfExpired(queue, timeLimit);

        Helping memory helping = Helping({
            owner: msg.sender,
            helpingType: doubleHelping ? HelpingType.DoubleHelping : HelpingType.TimedHelping,
            startBlock: block.number,
            depositsReceived: 0,
            exists: true
        });

        queue.helpings[msg.sender] = helping;

        if (queue.activeHelping.exists) {
            if (firstOnly) revert FirstOnlyUnsuccessful();          
            transferRewardToActiveHelping(queue);
            removeActiveHelpingIfExpired(queue, timeLimit); // Transferring the reward may have caused an active double helping to expire.
        }

        // Check if the reward transfer removed the active helping.
        if (queue.activeHelping.exists) {
            HeapNode memory node = HeapNode({addr: msg.sender, priority: premium});
            Heap.insert(queue.heapData, node);
        } else {
            // deposits received while this was the active helping. Start this at 1 to enable the first place bonus.
            // See https://github.com/eliphang/spicy-combos/blob/main/README.md#first-place-bonus .
            helping.depositsReceived = 1;
            queue.activeHelping = helping;
        }
    }

    function deposit() external payable {
        Balance storage balance = balances[msg.sender];

        balances[msg.sender].deposits += msg.value;
    }

    /// Increase the premium of the helping in the queue for the combo uniquely identified by the amount and blocks.
    function increasePremium(
        uint256 amountDigit1,
        uint256 amountDigit2,
        uint256 amountZeros,
        uint256 blocksDigit1,
        uint256 blocksDigit2,
        uint256 blocksZeros,
        uint256 increaseAmount
    )
        external
        payable
        comboValuesInRange(amountDigit1, amountDigit2, amountZeros, blocksDigit1, blocksDigit2, blocksZeros)
    {
        Balance storage balance = balances[msg.sender];
        // Make sure increasePremium() never calls an outside function or there could be a reentrancy attack.
        balance.deposits += msg.value;

        if (balance.deposits < increaseAmount) {
            revert NotEnoughDepositsForPremium(balance.deposits, increaseAmount);
        }

        unchecked {
            balance.deposits -= increaseAmount; // premiums go to the dev fund
        }

        uint256 comboId = computeComboId(
            amountDigit1,
            amountDigit2,
            amountZeros,
            blocksDigit1,
            blocksDigit2,
            blocksZeros
        );
    }

    function withdraw() external {}

    function removeHelping() external {}

    /// Get a queue's size, premium, and active address for the combo uniquely identified by the amount and blocks.
    /// @return size the size of the queue
    /// @return premium the premium that must be exceeded to take the active spot in this queue
    /// @return activeHelpingOwner the address of the owner of the active helping
    function queueInfo(
        uint256 amountDigit1,
        uint256 amountDigit2,
        uint256 amountZeros,
        uint256 blocksDigit1,
        uint256 blocksDigit2,
        uint256 blocksZeros
    )
        external
        view
        comboValuesInRange(amountDigit1, amountDigit2, amountZeros, blocksDigit1, blocksDigit2, blocksZeros)
        returns (
            uint256 size,
            uint256 premium,
            address activeHelpingOwner
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

    function removeActiveHelpingIfExpired(Queue storage queue, uint256 timeLimit) internal {
        // Check the active helping to see if it's expired
        Helping storage activeHelping = queue.activeHelping;
        bool expired;
        if (activeHelping.helpingType == HelpingType.DoubleHelping && activeHelping.depositsReceived >= 2) {
            expired = true;
        } else if (
            activeHelping.helpingType == HelpingType.TimedHelping && activeHelping.startBlock + timeLimit > block.number
        ) {
            expired = true;
        }
        if (expired) {
            delete queue.helpings[activeHelping.owner];
            HeapData storage heap = queue.heapData;
            if (Heap.size(heap) != 0) {
                HeapNode memory next = Heap.removeFirst(queue.heapData);
                queue.activeHelping = queue.helpings[next.addr];
                queue.activeHelping.startBlock = block.number; // when a helping becomes the active one, start the timer
            }
        }
    }

    function transferRewardToActiveHelping(Queue storage queue) internal {}
}
