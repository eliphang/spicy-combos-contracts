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
        uint256 expiration; // used by HelpingType.TimedHelping
        uint256 depositsReceived; // deposits received while this was the active helping
        bool usingCredits;
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

    event HelpingAdded(
        uint256 indexed comboId,
        address indexed owner,
        bool indexed usingCredits,
        bool doubleHelping,
        uint256 premium
    );
    event HelpingRemoved(uint256 indexed comboId, address indexed owner);
    event PremiumIncreased(uint256 indexed comboId, address indexed owner, uint256 newPremium);

    error ValueOutOfRange(string parameter, uint256 allowedMinimum, uint256 allowedMaximum);
    error NotEnoughAvailableCredits(uint256 availableCredits, uint256 comboPrice);
    error NotEnoughAvailableDeposits(uint256 availableDeposits, uint256 comboPrice);
    error NotEnoughAvailableDepositsForPremium(uint256 availableDeposits);
    error WithdrawAmountExceedsAvailableDeposits(uint256 availableDeposits);
    error FirstOnlyIncompatibleWithUseCredits();
    error FirstOnlyUnsuccessful();
    error HelpingNotFoundForCaller();
    error CannotIncreasePremiumOfActiveHelping();
    error RemovingActiveTimedHelpingNotAllowed();

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
    /// @param usingCredits Use credits instead of deposits for the base combo price (not including premium).
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
        bool usingCredits,
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
        uint256 timeLimit = computeValue(blocksDigit1, blocksDigit2, blocksZeros);

        if (usingCredits) {
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
        removeActiveHelpingIfExpired(comboId, comboPrice, timeLimit);

        Helping memory helping = Helping({
            owner: msg.sender,
            helpingType: doubleHelping ? HelpingType.DoubleHelping : HelpingType.TimedHelping,
            expiration: type(uint256).max,
            depositsReceived: 0,
            usingCredits: usingCredits,
            exists: true
        });

        if (combo.activeHelping.exists) {
            if (firstOnly) revert FirstOnlyUnsuccessful();
            ++combo.activeHelping.depositsReceived;
            removeActiveHelpingIfExpired(comboId, comboPrice, timeLimit); // Transferring the reward may cause the active double helping to expire.
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

        emit HelpingAdded(comboId, msg.sender, usingCredits, doubleHelping, premium);
    }

    /// Increase the premium of your helping in the queue for the combo uniquely identified by the amount and blocks.
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
        uint256 comboPrice = computeValue(amountDigit1, amountDigit2, amountZeros);
        uint256 timeLimit = computeValue(blocksDigit1, blocksDigit2, blocksZeros);

        Combo storage combo = combos[comboId];

        if (combo.activeHelping.owner == msg.sender) revert CannotIncreasePremiumOfActiveHelping();

        // First remove the active listing if it expired
        removeActiveHelpingIfExpired(comboId, comboPrice, timeLimit);

        // Check again if we have the active helping after possibly removing the previous one
        if (combo.activeHelping.owner == msg.sender) revert CannotIncreasePremiumOfActiveHelping();
        if (!combo.helpings[msg.sender].exists) revert HelpingNotFoundForCaller();

        // Remove the helping from the queue and re-add it with the new priority.
        QueueEntry memory entry = PriQueue.removeQueueEntry(combo.queue, msg.sender);
        entry.priority += increaseAmount;
        PriQueue.insert(combo.queue, entry);

        emit PremiumIncreased(comboId, msg.sender, entry.priority);
    }

    /// Withdraw some available deposits
    /// @param amount the amount to withdraw
    function withdraw(uint256 amount) external {
        Balance storage balance = balances[msg.sender];

        if (amount > balance.availableDeposits)
            revert WithdrawAmountExceedsAvailableDeposits(balance.availableDeposits);

        unchecked {
            balance.availableDeposits -= amount;
        }

        payable(msg.sender).transfer(amount);
    }

    /// Remove your helping from a combo, or an active double helping. The combo is identified by the amount and blocks.
    /// You will receive available credits or deposits. See https://github.com/eliphang/spicy-combos/blob/main/README.md
    function removeHelping(
        uint256 amountDigit1,
        uint256 amountDigit2,
        uint256 amountZeros,
        uint256 blocksDigit1,
        uint256 blocksDigit2,
        uint256 blocksZeros
    ) external comboValuesInRange(amountDigit1, amountDigit2, amountZeros, blocksDigit1, blocksDigit2, blocksZeros) {
        uint256 comboId = computeComboId(
            amountDigit1,
            amountDigit2,
            amountZeros,
            blocksDigit1,
            blocksDigit2,
            blocksZeros
        );
        uint256 timeLimit = computeValue(blocksDigit1, blocksDigit2, blocksZeros);
        uint256 comboPrice = computeValue(amountDigit1, amountDigit2, amountZeros);

        Combo storage combo = combos[comboId];
        if (!combo.helpings[msg.sender].exists) revert HelpingNotFoundForCaller();

        // First remove the active helping if it expired.
        removeActiveHelpingIfExpired(comboId, comboPrice, timeLimit);

        Helping storage helping = combo.helpings[msg.sender];

        // Removing the active helping might have removed our helping, so check again.
        if (helping.exists) {
            if (combo.activeHelping.owner == msg.sender) {
                HelpingType helpingType = combo.activeHelping.helpingType;
                if (helpingType == HelpingType.TimedHelping) revert RemovingActiveTimedHelpingNotAllowed();
                removeActiveHelping(comboId, comboPrice, timeLimit);
            } else {
                PriQueue.removeQueueEntry(combo.queue, msg.sender);
                Balance storage balance = balances[msg.sender];
                // We didn't get any deposits, so we get credits.
                balance.availableCredits += comboPrice;
                if (helping.usingCredits) {
                    balance.creditsInUse -= comboPrice;
                } else {
                    balance.depositsInUse -= comboPrice;
                }
                delete combo.helpings[msg.sender];
            }
        }

        emit HelpingRemoved(comboId, msg.sender);
    }

    /// Get info about a combo identified by the amount and blocks.
    /// @return queueLength the length of the queue
    /// @return premium the premium that must be exceeded to take the first position in the queue
    /// @return activeHelpingOwner the address of the owner of the active helping
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
            uint256 queueLength,
            uint256 premium,
            bool activeHelpingExists,
            address activeHelpingOwner,
            bool activeHelpingIsDoubleHelping,
            uint256 activeHelpingDeposits,
            uint256 activeHelpingExpiration,
            bool activeHelpingIsExpired
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
        Combo storage combo = combos[comboId];
        Helping storage activeHelping = combo.activeHelping;
        premium = PriQueue.getFirst(combo.queue).priority;
        queueLength = PriQueue.size(combo.queue);
        activeHelpingExists = activeHelping.exists;
        activeHelpingOwner = activeHelping.owner;
        activeHelpingIsDoubleHelping = activeHelping.helpingType == HelpingType.DoubleHelping;
        activeHelpingDeposits = activeHelping.depositsReceived;
        activeHelpingExpiration = activeHelping.expiration;
        activeHelpingIsExpired = isActiveHelpingExpired(comboId);
    }

    /// Get info about a helping owned by owner in the combo identified by the amount and blocks.
    /// @return queueLength the length of the queue
    /// @return premium the premium that must be exceeded to take the first position in the queue
    /// @return activeHelpingOwner the address of the owner of the active helping
    function helpingInfo(
        uint256 amountDigit1,
        uint256 amountDigit2,
        uint256 amountZeros,
        uint256 blocksDigit1,
        uint256 blocksDigit2,
        uint256 blocksZeros,
        address owner
    )
        external
        view
        comboValuesInRange(amountDigit1, amountDigit2, amountZeros, blocksDigit1, blocksDigit2, blocksZeros)
        returns (
            bool exists,
            bool isDoubleHelping,
            bool usingCredits,
            uint256 premium
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
        Combo storage combo = combos[comboId];
        Helping storage helping = combo.helpings[owner];
        exists = helping.exists;
        isDoubleHelping = helping.helpingType == HelpingType.DoubleHelping;
        usingCredits = helping.usingCredits;
        premium = PriQueue.getByAddress(combo.queue, owner).priority;
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

    function removeActiveHelpingIfExpired(
        uint256 comboId,
        uint256 comboPrice,
        uint256 timeLimit
    ) internal {
        if (isActiveHelpingExpired(comboId)) removeActiveHelping(comboId, comboPrice, timeLimit);
    }

    function removeActiveHelping(
        uint256 comboId,
        uint256 comboPrice,
        uint256 timeLimit
    ) internal {
        Combo storage combo = combos[comboId];
        Helping storage helping = combo.activeHelping;
        address owner = helping.owner;
        uint256 depositsReceived = helping.depositsReceived;
        Balance storage balance = balances[owner];
        if (depositsReceived == 0) {
            if (helping.helpingType == HelpingType.DoubleHelping)
                // We didn't get any deposits, so we get credits.
                balance.availableCredits += comboPrice;
        } else {
            uint256 earnedAmount = comboPrice * depositsReceived;
            if (helping.helpingType == HelpingType.TimedHelping) {
                // dev fund gets 10% of deposits after the first
                devFund += (earnedAmount - comboPrice) / 10;
                // we get 100% of the first deposit and 90% of each one after that
                earnedAmount = comboPrice + ((earnedAmount - comboPrice) * 9) / 10;
            }
            balance.availableDeposits += earnedAmount;
        }
        if (helping.usingCredits) {
            balance.creditsInUse -= comboPrice;
        } else {
            balance.depositsInUse -= comboPrice;
        }

        delete combo.helpings[owner];
        // If there's a queue, remove the first entry and make it the new active helping.
        if (PriQueue.size(combo.queue) != 0) {
            QueueEntry memory first = PriQueue.removeFirst(combo.queue);
            combo.activeHelping = combo.helpings[first.addr];
            combo.activeHelping.expiration = block.number + timeLimit; // When a helping becomes the active one, start the timer.
        }
        emit HelpingRemoved(comboId, owner);
    }

    function isActiveHelpingExpired(uint256 comboId) internal view returns (bool) {
        Helping storage helping = combos[comboId].activeHelping;
        return
            (helping.helpingType == HelpingType.DoubleHelping && helping.depositsReceived >= 2) ||
            (helping.helpingType == HelpingType.TimedHelping && block.number > helping.expiration);
    }
}
