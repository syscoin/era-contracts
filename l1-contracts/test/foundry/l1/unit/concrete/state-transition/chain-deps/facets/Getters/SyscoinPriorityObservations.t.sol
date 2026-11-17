// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {GettersFacet} from "contracts/state-transition/chain-deps/facets/Getters.sol";
import {PriorityTree} from "contracts/state-transition/libraries/PriorityTree.sol";

// SYSCOIN: Exercise the actual getter/storage boundary used by authenticated root checkpoints.
contract SyscoinPriorityObservationHarness is GettersFacet {
    using PriorityTree for PriorityTree.Tree;

    function initializeTree(uint256 start) external {
        s.priorityTree.setup(start);
    }

    function append(bytes32 hash, uint256 timestamp) external {
        uint256 index = s.priorityTree.getTotalPriorityTxs();
        s.priorityTree.push(hash);
        s.priorityOpsRequestTimestamp[index] = timestamp;
    }

    function process(uint256 count) external {
        s.priorityTree.unprocessedIndex += count;
    }
}

contract SyscoinPriorityObservationsTest is Test {
    SyscoinPriorityObservationHarness private getters;

    function setUp() public {
        getters = new SyscoinPriorityObservationHarness();
        getters.initializeTree(7);
    }

    function testTimestampUsesAbsoluteRootQueueIndexAndSurvivesProcessing() public {
        getters.append(keccak256("first"), 1000);
        getters.append(keccak256("second"), 1200);
        bytes32 root = getters.getPriorityTreeRoot();
        getters.process(1);
        assertEq(getters.getPriorityTransactionTimestamp(7), 1000);
        assertEq(getters.getPriorityTransactionTimestamp(8), 1200);
        assertEq(getters.getPriorityTreeRoot(), root);
        assertEq(getters.getFirstUnprocessedPriorityTx(), 8);
    }

    function testTimestampRejectsOutsideTreeInsteadOfPretendingZeroIsAnArrival() public {
        getters.append(keccak256("first"), 1000);
        vm.expectRevert("priority index outside tree");
        getters.getPriorityTransactionTimestamp(6);
        vm.expectRevert("priority index outside tree");
        getters.getPriorityTransactionTimestamp(8);
    }

    function testTreeHeightTracksActualNativeMerkleDepth() public {
        assertEq(getters.getPriorityTreeHeight(), 0);
        getters.append(keccak256("first"), 1000);
        assertEq(getters.getPriorityTreeHeight(), 0);
        getters.append(keccak256("second"), 1001);
        assertEq(getters.getPriorityTreeHeight(), 1);
        getters.append(keccak256("third"), 1002);
        assertEq(getters.getPriorityTreeHeight(), 2);
        getters.append(keccak256("fourth"), 1003);
        assertEq(getters.getPriorityTreeHeight(), 2);
    }
}
