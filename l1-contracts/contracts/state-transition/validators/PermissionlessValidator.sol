// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "../../common/ReentrancyGuard.sol";
import {IExecutor} from "../chain-interfaces/IExecutor.sol";
import {ICommitter} from "../chain-interfaces/ICommitter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable-v4/proxy/utils/Initializable.sol";

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice Smart contract used as an entry point for settling batches in Priority Mode.
/// It allows anyone to commit, prove, and execute batches in one go.
///
/// @dev The smart contract is intended to be used for Stage 1 ZK chains when their operators
/// fail to process priority transactions and priority mode is activated.
/// The chain contract is responsible for enforcing proper access control
/// (i.e., ensuring that only this contract can settle batches after Priority Mode is entered).
/// @dev Expected to be deployed as a TransparentUpgradeableProxy.
contract PermissionlessValidator is ReentrancyGuard, Initializable {
    constructor() {
        // Disable initialization to prevent Parity hack.
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    function initialize() external initializer reentrancyGuardInitializer {}

    /// @notice Commit, prove, and execute the same batch range atomically.
    /// @param _chainAddress The ZKsync chain contract address where to settle batches.
    /// @param _processBatchFrom The first batch in the range.
    /// @param _processBatchTo The last batch in the range.
    /// @param _commitData The calldata blob for the commit step.
    /// @param _proveData The calldata blob for the prove step.
    /// @param _executeData The calldata blob for the execute step.
    function settleBatchesSharedBridge(
        address _chainAddress,
        uint256 _processBatchFrom,
        uint256 _processBatchTo,
        bytes calldata _commitData,
        bytes calldata _proveData,
        bytes calldata _executeData
    ) external nonReentrant {
        ICommitter(_chainAddress).commitBatchesSharedBridge(
            _chainAddress,
            _processBatchFrom,
            _processBatchTo,
            _commitData
        );
        IExecutor(_chainAddress).proveBatchesSharedBridge(
            _chainAddress,
            _processBatchFrom,
            _processBatchTo,
            _proveData
        );
        IExecutor(_chainAddress).executeBatchesSharedBridge(
            _chainAddress,
            _processBatchFrom,
            _processBatchTo,
            _executeData
        );
    }

    /// @notice Settle two consecutive priority batches with one native aggregate proof.
    /// @dev The native committer accepts one batch per call. The executor checks the pair's
    /// stored commitments and processes each batch's priority operations in order.
    function settleBatchPairSharedBridge(
        address _chainAddress,
        uint256 _firstBatch,
        bytes[2] calldata _commitData,
        bytes calldata _proveData,
        bytes calldata _executeData
    ) external nonReentrant {
        uint256 secondBatch = _firstBatch + 1;
        ICommitter committer = ICommitter(_chainAddress);
        IExecutor executor = IExecutor(_chainAddress);
        committer.commitBatchesSharedBridge(_chainAddress, _firstBatch, _firstBatch, _commitData[0]);
        committer.commitBatchesSharedBridge(_chainAddress, secondBatch, secondBatch, _commitData[1]);
        executor.proveBatchesSharedBridge(_chainAddress, _firstBatch, secondBatch, _proveData);
        executor.executeBatchesSharedBridge(_chainAddress, _firstBatch, secondBatch, _executeData);
    }
}
