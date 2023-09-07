// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

// Adapted from https://github.com/zmitton/eth-heap/blob/916e884387a650ed83bce6b78f97c372b6dcc53f/contracts/Heap.sol

struct QueueData {
    QueueEntry[] nodes; // root is index 1; index 0 not used
    mapping(address => uint256) addrToNodeIndex;
}

struct QueueEntry {
    address addr;
    uint256 priority;
}

library PriQueue {
    uint256 constant ROOT_INDEX = 1;

    function insert(QueueData storage self, QueueEntry memory node) internal {
        if (self.nodes.length == 0) {
            self.nodes.push(node);
        } else {
            self.nodes.push(QueueEntry(address(0), 0)); // Create a new spot in the heap.
            _siftUp(self, node, self.nodes.length - 1); // Sift up the new node, also filling in the new spot.
        }
    }

    /// Remove and return the node with the highest priority
    function removeFirst(QueueData storage self) internal returns (QueueEntry memory node) {
        node = self.nodes[ROOT_INDEX];
        removeQueueEntry(self, node);
    }

    function removeQueueEntry(QueueData storage self, QueueEntry memory node) internal {
        uint256 nodeIndex = self.addrToNodeIndex[node.addr];
        uint256 lastIndex = self.nodes.length - 1;
        QueueEntry memory lastQueueEntry = self.nodes[lastIndex];

        delete self.addrToNodeIndex[node.addr]; // Delete the mapping from addr to QueueEntry Index.
        delete self.nodes[nodeIndex]; // Delete the QueueEntry struct for the removed node.
        self.nodes.pop(); // Reduce the heap size by one.

        if (nodeIndex != lastIndex) {
            // Put the last node in place of the removed node.
            _siftUp(self, lastQueueEntry, nodeIndex); // A sift up might first be required.
            _siftDown(self, self.nodes[nodeIndex], nodeIndex); // Sift down the node that has taken the removed node's place.
        }
    }

    function dump(QueueData storage self) internal view returns (QueueEntry[] storage) {
        return self.nodes;
    }

    function getByHeapId(QueueData storage self, address addr)
        internal
        view
        returns (QueueEntry storage)
    {
        return self.nodes[self.addrToNodeIndex[addr]];
    }

    function getFirst(QueueData storage self) internal view returns (QueueEntry storage) {
        return self.nodes[ROOT_INDEX];
    }

    function size(QueueData storage self) internal view returns (uint256) {
        return self.nodes.length > 0 ? self.nodes.length - 1 : 0;
    }

    function _siftUp(
        QueueData storage self,
        QueueEntry memory node,
        uint256 nodeIndex
    ) private {
        if (
            nodeIndex == ROOT_INDEX ||
            node.priority <= self.nodes[nodeIndex / 2].priority
        ) {
            _insert(self, node, nodeIndex);
        } else {
            _insert(self, self.nodes[nodeIndex / 2], nodeIndex);
            _siftUp(self, node, nodeIndex / 2);
        }
    }

    function _siftDown(
        QueueData storage self,
        QueueEntry memory node,
        uint256 nodeIndex
    ) private {
        uint256 length = self.nodes.length;
        uint256 childIndex = nodeIndex * 2;

        if (length <= childIndex) {
            _insert(self, node, nodeIndex);
        } else {
            QueueEntry memory largestChild = self.nodes[childIndex];
            if (
                length > childIndex + 1 &&
                self.nodes[childIndex + 1].priority > largestChild.priority
            ) {
                largestChild = self.nodes[++childIndex];
            }
            if (largestChild.priority <= node.priority) {
                _insert(self, node, nodeIndex);
            } else {
                _insert(self, largestChild, nodeIndex);
                _siftDown(self, node, childIndex);
            }
        }
    }

    function _insert(
        QueueData storage self,
        QueueEntry memory node,
        uint256 nodeIndex
    ) private {
        self.nodes[nodeIndex] = node;
        self.addrToNodeIndex[node.addr] = nodeIndex;
    }
}
