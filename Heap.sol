// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

// Adapted from https://github.com/zmitton/eth-heap/blob/916e884387a650ed83bce6b78f97c372b6dcc53f/contracts/Heap.sol

struct Data {
    Node[] nodes; // root is index 1; index 0 not used
    mapping(uint256 => uint256) heapIdToNodeIndex;
}

struct Node {
    uint256 heapId;
    uint256 priority;
}

library Heap {
    uint256 constant ROOT_INDEX = 1;

    function insert(Data storage self, Node memory node) internal {
        if (self.nodes.length == 0) {
            self.nodes.push(node);
        } else {
            self.nodes.push(Node(0, 0)); // Create a new spot in the heap.
            _siftUp(self, node, self.nodes.length - 1); // Sift up the new node, also filling in the new spot.
        }
    }

    /// Remove and return the node with the highest priority
    function removeMax(Data storage self) internal returns (Node memory node) {
        node = self.nodes[ROOT_INDEX];
        removeNode(self, node);
    }

    function removeNode(Data storage self, Node memory node) internal {
        uint256 nodeIndex = self.heapIdToNodeIndex[node.heapId];
        uint256 lastIndex = self.nodes.length - 1;
        Node memory lastNode = self.nodes[lastIndex];

        delete self.heapIdToNodeIndex[node.heapId]; // Delete the mapping from heapId to Node Index.
        delete self.nodes[nodeIndex]; // Delete the Node struct for the removed node.
        self.nodes.pop(); // Reduce the heap size by one.

        if (nodeIndex != lastIndex) {
            // Put the last node in place of the removed node.
            _siftUp(self, lastNode, nodeIndex); // A sift up might first be required.
            _siftDown(self, self.nodes[nodeIndex], nodeIndex); // Sift down the node that has taken the removed node's place.
        }
    }

    function dump(Data storage self) internal view returns (Node[] storage) {
        return self.nodes;
    }

    function getByHeapId(Data storage self, uint256 heapId)
        internal
        view
        returns (Node storage)
    {
        return self.nodes[self.heapIdToNodeIndex[heapId]];
    }

    function getMax(Data storage self) internal view returns (Node storage) {
        return self.nodes[ROOT_INDEX];
    }

    function size(Data storage self) internal view returns (uint256) {
        return self.nodes.length > 0 ? self.nodes.length - 1 : 0;
    }

    function _siftUp(
        Data storage self,
        Node memory node,
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
        Data storage self,
        Node memory node,
        uint256 nodeIndex
    ) private {
        uint256 length = self.nodes.length;
        uint256 childIndex = nodeIndex * 2;

        if (length <= childIndex) {
            _insert(self, node, nodeIndex);
        } else {
            Node memory largestChild = self.nodes[childIndex];
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
        Data storage self,
        Node memory node,
        uint256 nodeIndex
    ) private {
        self.nodes[nodeIndex] = node;
        self.heapIdToNodeIndex[node.heapId] = nodeIndex;
    }
}
