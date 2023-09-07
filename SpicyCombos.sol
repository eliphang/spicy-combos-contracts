// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";
import "./PriQueue.sol";

/// @custom:repo https://github.com/eliphang/spicy-combos-contracts
contract SpicyCombos is Ownable {
    enum HelpingType {
        DoubleHelping,
        TimedHelping
    }

    struct Combo {
        QueueData queue; // contains all helpings after the active one
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
        uint256 availableDeposits;
        uint256 depositsInUse;
        uint256 availableCredits;
        uint256 creditsInUse;
    }

    uint256 public devFund = 0;

    /// the minimum cost of a helping. All combo costs will be a multiple of this.
    uint256 public immutable minValue;

    mapping(uint256 => Combo) combos; // The keys are comboIds.
    mapping(address => Balance) public balances;

    error ValueOutOfRange(string parameter, uint256 allowedMinimum, uint256 allowedMaximum);
    error NotEnoughAvailableCredits(uint256 availableCredits, uint256 comboPrice);
    error NotEnoughAvailableDeposits(uint256 availableDeposits, uint256 comboPrice);
    error NotEnoughAvailableDepositsForPremium(uint256 availableDeposits);
    error WithdrawAmountExceedsAvailableDeposits(uint256 availableDeposits);
    error FirstOnlyIncompatibleWithUseCredits();
    error FirstOnlyUnsuccessful();
    error HelpingNotFoundForCaller();
    error CannotIncreasePremiumOfActiveHelping();

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
        deposit();
    }

    /// Withdraw all funds set aside for the dev fund.
    /// @dev The contract "owner" is considered the destination address of the dev fund.
    /// @dev The owner has no other privilege than to receive the amount set aside in the dev fund.
    function withdrawDevFund() external {
        // Disallow reentrancy from the devFund to withdraw more than its share.
        uint256 withdrawAmount = devFund;
        devFund = 0;
        owner().call{value: withdrawAmount}(""); // The devFund might be a contract, so forward all gas.
    }

    /// Add a helping to a combo. The first six parameters uniquely define a combo.
    /// @param amountDigit1 first significant digit in the amount.
    /// @param amountDigit2 second significant digit in the amount (or zero if there is only one significant digit).
    /// @param amountZeros number of zeros to add to the minimum value for amount.
    /// @param blocksDigit1 first significant digit in the number of blocks for timed helpings.
    /// @param blocksDigit2 second significant digit in the number of blocks (or zero if there is only one significant digit).
    /// @param blocksZeros number of zeros to add to the number of blocks.
    /// @param doubleHelping Is this a double helping? If not, it's a timed helping.
    /// @param useCredits Use credits instead of deposits for the base combo price (not including premium).
    /// @param firstOnly Use this if you want a first place bonus and fail (revert) if you don't get it.
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
        bool firstOnly,
        uint256 premium
    )
        external
        payable
        comboValuesInRange(amountDigit1, amountDigit2, amountZeros, blocksDigit1, blocksDigit2, blocksZeros)
    {
        // Update caller's balance.

        Balance storage balance = balances[msg.sender];
        // Make sure addHelping() never calls an outside function or there could be a reentrancy attack.
        balance.availableDeposits += msg.value;

        if (balance.availableDeposits < premium) {
            revert NotEnoughAvailableDepositsForPremium(balance.availableDeposits);
        }

        unchecked {
            balance.availableDeposits -= premium;
        }

        devFund += premium;

        uint256 comboId = computeComboId(
            amountDigit1,
            amountDigit2,
            amountZeros,
            blocksDigit1,
            blocksDigit2,
            blocksZeros
        );
        uint256 comboPrice = computeValue(amountDigit1, amountDigit2, amountZeros);

        if (useCredits) {
            if (firstOnly) {
                revert FirstOnlyIncompatibleWithUseCredits();
            }
            if (balance.availableCredits < comboPrice) {
                revert NotEnoughAvailableCredits(balance.availableCredits, comboPrice);
            }
            balance.availableCredits -= comboPrice;
            balance.creditsInUse += comboPrice;
        } else {
            // use deposits
            if (balance.availableDeposits < comboPrice) {
                revert NotEnoughAvailableDeposits(balance.availableDeposits, comboPrice);
            }
            balance.availableDeposits -= comboPrice;
            balance.depositsInUse += comboPrice;
        }

        // Update queue.

        Combo storage combo = combos[comboId];
        uint256 timeLimit = computeValue(blocksDigit1, blocksDigit2, blocksZeros);
        removeActiveHelpingIfExpired(combo, timeLimit);

        Helping memory helping = Helping({
            owner: msg.sender,
            helpingType: doubleHelping ? HelpingType.DoubleHelping : HelpingType.TimedHelping,
            startBlock: block.number,
            depositsReceived: 0,
            exists: true
        });

        if (combo.activeHelping.exists) {
            if (firstOnly) revert FirstOnlyUnsuccessful();
            ++combo.activeHelping.depositsReceived;
            removeActiveHelpingIfExpired(combo, timeLimit); // Transferring the reward may cause the active double helping to expire.
        } else {
            // deposits received while this was the active helping. Start this at 1 to enable the first place bonus.
            // See https://github.com/eliphang/spicy-combos/blob/main/README.md#first-place-bonus .
            helping.depositsReceived = 1;
        }

        combo.helpings[msg.sender] = helping;

        // Check if the reward transfer removed the active helping.
        if (combo.activeHelping.exists) {
            QueueEntry memory entry = QueueEntry({addr: msg.sender, priority: premium});
            PriQueue.insert(combo.queue, entry);
        } else {
            combo.activeHelping = helping;
        }
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
        balance.availableDeposits += msg.value;

        if (balance.availableDeposits < increaseAmount) {
            revert NotEnoughAvailableDepositsForPremium(balance.availableDeposits);
        }

        unchecked {
            balance.availableDeposits -= increaseAmount;
        }

        devFund += increaseAmount;

        uint256 comboId = computeComboId(
            amountDigit1,
            amountDigit2,
            amountZeros,
            blocksDigit1,
            blocksDigit2,
            blocksZeros
        );

        Combo storage combo = combos[comboId];
        if (combo.activeHelping.owner == msg.sender) revert CannotIncreasePremiumOfActiveHelping();
        if (!combo.helpings[msg.sender].exists) revert HelpingNotFoundForCaller();

        // Remove the helping from the queue and re-add it with the new priority.
        QueueEntry memory entry = PriQueue.removeQueueEntry(combo.queue, msg.sender);
        entry.priority += increaseAmount;
        PriQueue.insert(combo.queue, entry);
    }

    function withdraw(uint256 amount) external {
        Balance storage balance = balances[msg.sender];

        if (amount > balance.availableDeposits)
            revert WithdrawAmountExceedsAvailableDeposits(balance.availableDeposits);

        unchecked {
            balance.availableDeposits -= amount;
        }

        payable(msg.sender).transfer(amount);
    }

    function removeHelping() external {}

    /// Get a combo's queue size, premium, and active address for the combo uniquely identified by the amount and blocks.
    /// @return queueSize the size of the queue
    /// @return premium the premium that must be exceeded to take the first position in the queue
    /// @return activeOwner the address of the owner of the active helping
    function comboInfo(
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
            uint256 queueSize,
            uint256 premium,
            address activeOwner
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

    function deposit() public payable {
        balances[msg.sender].availableDeposits += msg.value;
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

    function removeActiveHelpingIfExpired(Combo storage combo, uint256 timeLimit) internal {
        Helping storage active = combo.activeHelping;
        if (
            (active.helpingType == HelpingType.DoubleHelping && active.depositsReceived >= 2) ||
            (active.helpingType == HelpingType.TimedHelping && active.startBlock + timeLimit > block.number)
        ) {
            delete combo.helpings[active.owner];
            // If there's a queue, remove the first entry and make it the new active helping.
            if (PriQueue.size(combo.queue) != 0) {
                QueueEntry memory first = PriQueue.removeFirst(combo.queue);
                combo.activeHelping = combo.helpings[first.addr];
                combo.activeHelping.startBlock = block.number; // When a helping becomes the active one, start the timer.
            }
        }
    }
}
