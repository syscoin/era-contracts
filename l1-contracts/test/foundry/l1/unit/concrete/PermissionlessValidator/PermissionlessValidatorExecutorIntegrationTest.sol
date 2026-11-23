// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ExecutorTest} from "../BatchProcessing/_Executor_Shared.t.sol";
import {Utils} from "../Utils/Utils.sol";
import {InvalidTxCountInPriorityMode} from "contracts/common/L1ContractErrors.sol";
import {MismatchNumberOfLayer1Txs} from "contracts/state-transition/L1StateTransitionErrors.sol";
import {IExecutor} from "contracts/state-transition/chain-interfaces/IExecutor.sol";
import {CommitBatchInfoZKsyncOS} from "contracts/state-transition/chain-interfaces/ICommitter.sol";
import {PriorityOpsBatchInfo} from "contracts/state-transition/libraries/PriorityTree.sol";
import {IL1DAValidator, L1DAValidatorOutput} from "contracts/state-transition/chain-interfaces/IL1DAValidator.sol";
import {SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME} from "contracts/common/SyscoinConfig.sol";
import {Merkle} from "contracts/common/libraries/Merkle.sol";
import {PRIORITY_EXPIRATION, REQUIRED_L2_GAS_PRICE_PER_PUBDATA} from "contracts/common/Config.sol";
import {L2TransactionRequestDirect} from "contracts/core/bridgehub/IBridgehubBase.sol";

contract PermissionlessValidatorExecutorIntegrationTest is ExecutorTest {
    bytes32 private firstPriorityHash;

    function isZKsyncOS() internal pure override returns (bool) {
        return true;
    }

    function setUp() public {
        _activatePriorityMode();
    }

    function _activatePriorityMode() internal {
        vm.prank(owner);
        admin.makePermanentRollup();
        firstPriorityHash = _enqueuePriorityRequest();
        vm.prank(owner);
        admin.permanentlyAllowPriorityMode();
        vm.warp(block.timestamp + PRIORITY_EXPIRATION + 1);
        admin.activatePriorityMode();
    }

    function _enqueuePriorityRequest() private returns (bytes32) {
        address prioritySender = makeAddr("prioritySender");
        uint256 l2GasLimit = 1_000_000;
        uint256 baseCost = mailbox.l2TransactionBaseCost(10_000_000, l2GasLimit, REQUIRED_L2_GAS_PRICE_PER_PUBDATA);
        vm.deal(prioritySender, baseCost);
        vm.prank(prioritySender);
        return dummyBridgehub.requestL2TransactionDirect{value: baseCost}(
            L2TransactionRequestDirect({
                chainId: l2ChainId,
                mintValue: baseCost,
                l2Contract: makeAddr("l2Contract"),
                l2Value: 0,
                l2Calldata: "",
                l2GasLimit: l2GasLimit,
                l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
                factoryDeps: new bytes[](0),
                refundRecipient: prioritySender
            })
        );
    }

    function test_settleBatchesSharedBridge_withExecutor() public {
        PriorityOpsBatchInfo[] memory priorityOps = Utils.generatePriorityOps(1, 1);
        CommitBatchInfoZKsyncOS memory commitInfo = _prepareCommitInfo(priorityOps);
        _mockDAValidator(commitInfo.batchNumber);

        (
            uint256 txFrom,
            uint256 txTo,
            bytes memory commitData,
            bytes memory proveData,
            bytes memory executeData
        ) = _encodeSettleData(commitInfo, priorityOps);

        permissionlessValidator.settleBatchesSharedBridge(
            address(executor),
            txFrom,
            txTo,
            commitData,
            proveData,
            executeData
        );

        assertEq(getters.getTotalBatchesCommitted(), 1);
        assertEq(getters.getTotalBatchesVerified(), 1);
        assertEq(getters.getTotalBatchesExecuted(), 1);
        assertEq(getters.l2LogsRootHash(1), commitInfo.l2LogsTreeRoot);
    }

    function test_settleBatchPairSharedBridge_processesBothPriorityRequests() public {
        (bytes[2] memory commits, bytes memory prove, bytes memory execute) = _pairData(0, true);
        permissionlessValidator.settleBatchPairSharedBridge(address(executor), 1, commits, prove, execute);

        assertEq(getters.getTotalBatchesCommitted(), 2);
        assertEq(getters.getTotalBatchesVerified(), 2);
        assertEq(getters.getTotalBatchesExecuted(), 2);
        assertEq(getters.getFirstUnprocessedPriorityTx(), 2);
        assertNotEq(getters.storedBatchHash(1), getters.storedBatchHash(2));
    }

    function test_settleBatchPairSharedBridge_ineligibleSecondBatchRollsBackFirstCommit() public {
        (bytes[2] memory commits, bytes memory prove, bytes memory execute) = _pairData(1, true);
        vm.expectRevert(abi.encodeWithSelector(InvalidTxCountInPriorityMode.selector, 1, 1));
        permissionlessValidator.settleBatchPairSharedBridge(address(executor), 1, commits, prove, execute);
        _assertPairRolledBack();
    }

    function test_settleBatchPairSharedBridge_failedExecutionRollsBackBothCommitsAndProof() public {
        (bytes[2] memory commits, bytes memory prove, bytes memory execute) = _pairData(0, false);
        vm.expectRevert(abi.encodeWithSelector(MismatchNumberOfLayer1Txs.selector, 1, 0));
        permissionlessValidator.settleBatchPairSharedBridge(address(executor), 1, commits, prove, execute);
        _assertPairRolledBack();
    }

    function _assertPairRolledBack() private view {
        assertEq(getters.getTotalBatchesCommitted(), 0);
        assertEq(getters.getTotalBatchesVerified(), 0);
        assertEq(getters.getTotalBatchesExecuted(), 0);
        assertEq(getters.getFirstUnprocessedPriorityTx(), 0);
        assertEq(getters.getPriorityQueueSize(), 2);
        assertEq(getters.storedBatchHash(1), bytes32(0));
        assertEq(getters.storedBatchHash(2), bytes32(0));
    }

    function _pairData(
        uint256 _secondL2TxCount,
        bool _includeSecondExecutionItem
    ) private returns (bytes[2] memory commits, bytes memory prove, bytes memory execute) {
        bytes32 secondPriorityHash = _enqueuePriorityRequest();
        PriorityOpsBatchInfo[] memory ops = new PriorityOpsBatchInfo[](2);
        IExecutor.StoredBatchInfo[] memory batches = new IExecutor.StoredBatchInfo[](2);
        IExecutor.StoredBatchInfo memory previous = genesisStoredBatchInfo;
        for (uint256 i = 0; i < 2; ++i) {
            bytes32 item = i == 0 ? firstPriorityHash : secondPriorityHash;
            ops[i].itemHashes = new bytes32[](1);
            ops[i].itemHashes[0] = item;
            ops[i].leftPath = new bytes32[](1);
            ops[i].rightPath = new bytes32[](1);
            if (i == 0) ops[i].rightPath[0] = secondPriorityHash;
            else ops[i].leftPath[0] = firstPriorityHash;

            CommitBatchInfoZKsyncOS[] memory commit = new CommitBatchInfoZKsyncOS[](1);
            commit[0] = _buildCommitInfoZKsyncOS(_rollingHash(ops[i].itemHashes), 1);
            commit[0].batchNumber = uint64(i + 1);
            commit[0].firstBlockNumber = uint64(2 * i + 1);
            commit[0].lastBlockNumber = uint64(2 * i + 2);
            commit[0].newStateCommitment = keccak256(abi.encode(previous.batchHash, item));
            if (i == 1) commit[0].numberOfLayer2Txs = _secondL2TxCount;
            _mockDAValidator(commit[0].batchNumber);
            (, , commits[i]) = Utils.encodeCommitBatchesDataZKsyncOS(previous, commit);
            batches[i] = _buildStoredBatchInfoZKsyncOS(commit[0]);
            previous = batches[i];
        }
        (, , prove) = Utils.encodeProveBatchesData(genesisStoredBatchInfo, batches, proofInput);
        if (!_includeSecondExecutionItem) ops[1].itemHashes = new bytes32[](0);
        (, , execute) = Utils.encodeExecuteBatchesDataZeroLogs(batches, ops);
    }

    function _prepareCommitInfo(
        PriorityOpsBatchInfo[] memory priorityOps
    ) internal returns (CommitBatchInfoZKsyncOS memory commitInfo) {
        bytes32 rollingHash = _rollingHash(priorityOps[0].itemHashes);
        bytes32[] memory merkleItemHashes = new bytes32[](priorityOps[0].itemHashes.length);
        for (uint256 i = 0; i < priorityOps[0].itemHashes.length; ++i) {
            merkleItemHashes[i] = priorityOps[0].itemHashes[i];
        }
        bytes32 expectedRoot = Merkle.calculateRootPaths(
            priorityOps[0].leftPath,
            priorityOps[0].rightPath,
            0,
            merkleItemHashes
        );
        executor.setPriorityTreeHistoricalRoot(expectedRoot);
        commitInfo = _buildCommitInfoZKsyncOS(rollingHash, priorityOps[0].itemHashes.length);
    }

    function _mockDAValidator(uint256 batchNumber) internal {
        // SYSCOIN: Compact edge DA commits to a reference root instead of KZG blob arrays.
        bytes32[] memory blobHashes = new bytes32[](0);
        bytes32[] memory blobCommitments = new bytes32[](0);
        vm.mockCall(
            rollupL1DAValidator,
            abi.encodeWithSelector(IL1DAValidator.checkDA.selector, l2ChainId, batchNumber),
            abi.encode(
                L1DAValidatorOutput({
                    stateDiffHash: bytes32(0),
                    blobsLinearHashes: blobHashes,
                    blobsOpeningCommitments: blobCommitments
                })
            )
        );
    }

    function _encodeSettleData(
        CommitBatchInfoZKsyncOS memory commitInfo,
        PriorityOpsBatchInfo[] memory priorityOps
    )
        internal
        view
        returns (
            uint256 txFrom,
            uint256 txTo,
            bytes memory commitData,
            bytes memory proveData,
            bytes memory executeData
        )
    {
        CommitBatchInfoZKsyncOS[] memory commitInfos = new CommitBatchInfoZKsyncOS[](1);
        commitInfos[0] = commitInfo;
        (txFrom, txTo, commitData) = Utils.encodeCommitBatchesDataZKsyncOS(genesisStoredBatchInfo, commitInfos);

        IExecutor.StoredBatchInfo[] memory storedArray = new IExecutor.StoredBatchInfo[](1);
        storedArray[0] = _buildStoredBatchInfoZKsyncOS(commitInfo);

        (, , proveData) = Utils.encodeProveBatchesData(genesisStoredBatchInfo, storedArray, proofInput);
        (, , executeData) = Utils.encodeExecuteBatchesDataZeroLogs(storedArray, priorityOps);
    }

    /// @dev Builds a ZKsync OS commit batch info for a priority-mode batch (no L2 txs).
    function _buildCommitInfoZKsyncOS(
        bytes32 priorityOpsHash,
        uint256 numberOfLayer1Txs
    ) internal view returns (CommitBatchInfoZKsyncOS memory info) {
        info = newCommitBatchInfoZKsyncOS;
        info.daCommitmentScheme = SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME;
        info.numberOfLayer1Txs = numberOfLayer1Txs;
        info.numberOfLayer2Txs = 0;
        info.priorityOperationsHash = priorityOpsHash;
        // No interop roots are submitted during execution so the accumulated value is bytes32(0)
        info.dependencyRootsRollingHash = bytes32(0);
    }

    /// @dev Replicates the stored batch info that _commitOneBatchZKsyncOS produces for the given commit info.
    function _buildStoredBatchInfoZKsyncOS(
        CommitBatchInfoZKsyncOS memory commitInfo
    ) internal view returns (IExecutor.StoredBatchInfo memory) {
        return
            IExecutor.StoredBatchInfo({
                batchNumber: commitInfo.batchNumber,
                batchHash: commitInfo.newStateCommitment,
                indexRepeatedStorageChanges: 0,
                numberOfLayer1Txs: commitInfo.numberOfLayer1Txs,
                priorityOperationsHash: commitInfo.priorityOperationsHash,
                l2LogsTreeRoot: commitInfo.l2LogsTreeRoot,
                dependencyRootsRollingHash: commitInfo.dependencyRootsRollingHash,
                timestamp: 0,
                commitment: _batchOutputHash(commitInfo)
            });
    }

    /// @dev Mirror the batchOutputHash formula from Committer._commitOneBatchZKsyncOS.
    /// Note: the chain id is not part of the batch output; it is committed via the chain config
    /// section of the batch proof public input instead.
    function _batchOutputHash(CommitBatchInfoZKsyncOS memory c) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    c.firstBlockTimestamp,
                    c.lastBlockTimestamp,
                    uint256(c.daCommitmentScheme),
                    c.daCommitment,
                    c.numberOfLayer1Txs,
                    c.numberOfLayer2Txs,
                    c.priorityOperationsHash,
                    c.l2LogsTreeRoot,
                    bytes32(0), // no system-contract upgrade tx
                    c.dependencyRootsRollingHash,
                    c.slChainId,
                    c.edgeDARefsRoot
                )
            );
    }

    function _rollingHash(bytes32[] memory hashes) internal pure returns (bytes32) {
        bytes32 rollingHash = keccak256("");
        for (uint256 i = 0; i < hashes.length; ++i) {
            rollingHash = keccak256(bytes.concat(rollingHash, hashes[i]));
        }
        return rollingHash;
    }
}
