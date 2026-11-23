// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "../../common/ReentrancyGuard.sol";
import {IExecutor} from "../chain-interfaces/IExecutor.sol";
import {ICommitter} from "../chain-interfaces/ICommitter.sol";
import {BatchDecoder} from "../libraries/BatchDecoder.sol";
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
    // SYSCOIN: V1 wrapper for two native zkOS commit blobs. Its first byte is outside both native encodings.
    bytes4 private constant PRIORITY_PAIR_V1 = 0x53595001;

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
    /// @param _commitData Native commit data, or 0x53595001 followed by abi.encode(bytes[2]) for a zkOS pair.
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
        _commit(_chainAddress, _processBatchFrom, _processBatchTo, _commitData);
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

    function _commit(address _chainAddress, uint256 _from, uint256 _to, bytes calldata _data) private {
        ICommitter committer = ICommitter(_chainAddress);
        if (_to > _from && _to - _from == 1 && _data.length >= 4 && bytes4(_data[:4]) == PRIORITY_PAIR_V1) {
            bytes[2] memory commits = abi.decode(_data[4:], (bytes[2]));
            bytes1 osVersion = bytes1(BatchDecoder.SUPPORTED_ENCODING_VERSION_COMMIT_ZKSYNC_OS);
            if (bytes1(commits[0]) == osVersion && bytes1(commits[1]) == osVersion) {
                // Native commits authenticate their predecessor and admit one batch at a time.
                committer.commitBatchesSharedBridge(_chainAddress, _from, _from, commits[0]);
                committer.commitBatchesSharedBridge(_chainAddress, _to, _to, commits[1]);
                return;
            }
        }
        committer.commitBatchesSharedBridge(_chainAddress, _from, _to, _data);
    }
}
