// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Test.sol";

import {Utils, TEST_ROLLUP_DA_MANAGER_OWNER} from "../Utils/Utils.sol";
import {ExecutorTest} from "./_Executor_Shared.t.sol";

import {CommitBatchInfoZKsyncOS} from "contracts/state-transition/chain-interfaces/ICommitter.sol";
import {L2DACommitmentScheme, TESTNET_COMMIT_TIMESTAMP_NOT_OLDER} from "contracts/common/Config.sol";
import {
    SYSCOIN_BITCOIN_DA_PRECOMPILE,
    SYSCOIN_EDGE_DA_REFS_DOMAIN,
    SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME
} from "contracts/common/SyscoinConfig.sol";
import {
    BatchNumberMismatch,
    BatchTimestampGreaterThanLastL2BlockTimestamp,
    IncorrectBatchChainId,
    InvalidBlockRange,
    L2TimestampTooBig,
    TimeNotReached
} from "contracts/common/L1ContractErrors.sol";
import {
    MismatchL2DACommitmentScheme,
    SettlementLayerChainIdMismatch,
    SyscoinEdgeDACommitmentMismatch,
    SyscoinEdgeDANotAvailable,
    SyscoinEdgeDAPrecompileCallFailed,
    SyscoinEdgeDARefInputMalformed,
    SyscoinEdgeDARefsRootMismatch
} from "contracts/state-transition/L1StateTransitionErrors.sol";

// SYSCOIN: This entire downstream test adaptation exercises the canonical V32 compact-DA
// commitment, edge-reference, and settlement-layer invariants; every divergence in this file is intentional.
bytes32 constant SYSCOIN_TEST_BATCH_DA_REF = keccak256("SYSCOIN_TEST_BATCH_DA_REF");

contract SyscoinBitcoinDAEcho {
    fallback() external {
        assembly {
            calldatacopy(0, 0, calldatasize())
            return(0, calldatasize())
        }
    }
}

contract SyscoinBitcoinDARevert {
    fallback() external {
        bytes32 dataHash;
        assembly {
            dataHash := calldataload(0)
        }
        if (dataHash == SYSCOIN_TEST_BATCH_DA_REF) {
            assembly {
                calldatacopy(0, 0, calldatasize())
                return(0, calldatasize())
            }
        }
        assembly {
            revert(0, 0)
        }
    }
}

contract SyscoinBitcoinDAEmpty {
    fallback() external {
        bytes32 dataHash;
        assembly {
            dataHash := calldataload(0)
        }
        if (dataHash == SYSCOIN_TEST_BATCH_DA_REF) {
            assembly {
                calldatacopy(0, 0, calldatasize())
                return(0, calldatasize())
            }
        }
        assembly {
            return(0, 0)
        }
    }
}

contract SyscoinBitcoinDAWrong {
    fallback() external {
        bytes32 dataHash;
        assembly {
            dataHash := calldataload(0)
        }
        if (dataHash == SYSCOIN_TEST_BATCH_DA_REF) {
            assembly {
                calldatacopy(0, 0, calldatasize())
                return(0, calldatasize())
            }
        }
        assembly {
            mstore(0, not(calldataload(0)))
            return(0, 32)
        }
    }
}

contract CommittingTest is ExecutorTest {
    function isZKsyncOS() internal pure override returns (bool) {
        return true;
    }

    function setUp() public {}

    function _canonicalSyscoinBatch() internal view returns (CommitBatchInfoZKsyncOS memory batch) {
        batch = newCommitBatchInfoZKsyncOS;
        batch.operatorDAInput = abi.encodePacked(SYSCOIN_TEST_BATCH_DA_REF);
        batch.daCommitment = keccak256(batch.operatorDAInput);
        batch.daCommitmentScheme = SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME;
    }

    function _configureSyscoinCompactDA() internal {
        if (SYSCOIN_BITCOIN_DA_PRECOMPILE.code.length == 0) {
            vm.etch(SYSCOIN_BITCOIN_DA_PRECOMPILE, address(new SyscoinBitcoinDAEcho()).code);
        }

        // SYSCOIN: Deploy the canonical sibling-package artifact through the
        // existing bytecode utility so test coverage does not alter the L1
        // package's global compiler remappings or production bytecode metadata.
        address syscoinValidator = Utils.deploySyscoinL1DAValidatorZKsyncOSBytecode();
        vm.prank(TEST_ROLLUP_DA_MANAGER_OWNER);
        rollupDAManager.updateDAPair(syscoinValidator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME, true);
        vm.prank(address(owner));
        admin.setDAValidatorPair(syscoinValidator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME);
    }

    function _commitCanonicalSyscoinBatch(
        CommitBatchInfoZKsyncOS memory _batch,
        bytes memory _expectedRevert
    ) internal {
        _configureSyscoinCompactDA();

        CommitBatchInfoZKsyncOS[] memory batches = new CommitBatchInfoZKsyncOS[](1);
        batches[0] = _batch;
        (uint256 processFrom, uint256 processTo, bytes memory commitData) = Utils.encodeCommitBatchesDataZKsyncOS(
            genesisStoredBatchInfo,
            batches
        );

        if (_expectedRevert.length != 0) {
            vm.expectRevert(_expectedRevert);
        }
        vm.prank(validator);
        committer.commitBatchesSharedBridge(address(0), processFrom, processTo, commitData);
    }

    function test_SuccessfullyCommitBatchWithSyscoinCompactDA() public {
        _commitCanonicalSyscoinBatch(_canonicalSyscoinBatch(), "");
    }

    function test_RevertWhen_CommittingWithWrongL2DACommitmentScheme() public {
        CommitBatchInfoZKsyncOS memory batch = _canonicalSyscoinBatch();
        batch.daCommitmentScheme = L2DACommitmentScheme.NONE;

        _commitCanonicalSyscoinBatch(
            batch,
            abi.encodeWithSelector(
                MismatchL2DACommitmentScheme.selector,
                uint256(L2DACommitmentScheme.NONE),
                uint256(SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME)
            )
        );
    }

    function test_RevertWhen_BatchNumberMismatch() public {
        CommitBatchInfoZKsyncOS memory batch = _canonicalSyscoinBatch();
        batch.batchNumber = 5;

        _commitCanonicalSyscoinBatch(batch, abi.encodeWithSelector(BatchNumberMismatch.selector, 1, 5));
    }

    function test_RevertWhen_IncorrectBatchChainId() public {
        CommitBatchInfoZKsyncOS memory batch = _canonicalSyscoinBatch();
        batch.chainId = 999;

        _commitCanonicalSyscoinBatch(batch, abi.encodeWithSelector(IncorrectBatchChainId.selector, 999, l2ChainId));
    }

    function test_RevertWhen_IncorrectBatchSLChainId() public {
        CommitBatchInfoZKsyncOS memory batch = _canonicalSyscoinBatch();
        batch.slChainId = 999;

        _commitCanonicalSyscoinBatch(batch, abi.encodeWithSelector(SettlementLayerChainIdMismatch.selector));
    }

    function test_RevertWhen_InvalidBlockRange() public {
        CommitBatchInfoZKsyncOS memory batch = _canonicalSyscoinBatch();
        batch.firstBlockNumber = 10;
        batch.lastBlockNumber = 5;

        _commitCanonicalSyscoinBatch(batch, abi.encodeWithSelector(InvalidBlockRange.selector, 1, 10, 5));
    }

    function test_RevertWhen_L2TimestampTooBig() public {
        CommitBatchInfoZKsyncOS memory batch = _canonicalSyscoinBatch();
        batch.lastBlockTimestamp = uint64(block.timestamp + 365 days);

        _commitCanonicalSyscoinBatch(batch, abi.encodeWithSelector(L2TimestampTooBig.selector));
    }

    function test_RevertWhen_TimeNotReached() public {
        CommitBatchInfoZKsyncOS memory batch = _canonicalSyscoinBatch();
        batch.firstBlockTimestamp = 1;

        _commitCanonicalSyscoinBatch(
            batch,
            abi.encodeWithSelector(TimeNotReached.selector, 1, block.timestamp - TESTNET_COMMIT_TIMESTAMP_NOT_OLDER)
        );
    }

    /// @notice Reverts when the batch-level first timestamp exceeds its last timestamp.
    /// @dev Both timestamps remain inside the accepted time window so the ordering check is reached.
    function test_RevertWhen_FirstBlockTimestampGreaterThanLastBlockTimestamp() public {
        CommitBatchInfoZKsyncOS memory batch = _canonicalSyscoinBatch();
        batch.firstBlockTimestamp = uint64(currentTimestamp);
        batch.lastBlockTimestamp = uint64(currentTimestamp - 1);

        _commitCanonicalSyscoinBatch(
            batch,
            abi.encodeWithSelector(BatchTimestampGreaterThanLastL2BlockTimestamp.selector)
        );
    }

    /// @notice The strict timestamp-order guard permits equal first and last timestamps.
    function test_SuccessfullyCommit_WhenFirstEqualsLastBlockTimestamp() public {
        CommitBatchInfoZKsyncOS memory batch = _canonicalSyscoinBatch();
        uint64 equalTimestamp = uint64(currentTimestamp - 5);
        batch.firstBlockTimestamp = equalTimestamp;
        batch.lastBlockTimestamp = equalTimestamp;

        _commitCanonicalSyscoinBatch(batch, "");
    }

    function _syscoinEdgeDARefsInput(
        uint256 _edgeChainId,
        uint256 _edgeBatchNumber,
        bytes memory _refs
    ) internal pure returns (bytes memory input, bytes32 root, bytes32 commitment) {
        commitment = keccak256(_refs);
        input = abi.encode(uint8(1), _edgeChainId, _edgeBatchNumber, commitment, _refs);
        bytes32 refHash = keccak256(
            abi.encodePacked(
                SYSCOIN_EDGE_DA_REFS_DOMAIN,
                _edgeChainId,
                _edgeBatchNumber,
                commitment,
                _refs.length / 32,
                _refs
            )
        );
        root = keccak256(abi.encodePacked(bytes32(0), refHash));
    }

    function _commitSyscoinWithEdgeRefs(bytes memory _input, bytes32 _root, bytes memory _expectedRevert) internal {
        CommitBatchInfoZKsyncOS memory batch = _canonicalSyscoinBatch();
        batch.edgeDARefsInput = _input;
        batch.edgeDARefsRoot = _root;
        _commitCanonicalSyscoinBatch(batch, _expectedRevert);
    }

    function _splitSyscoinEdgeDARefs(
        uint256 _firstCount,
        uint256 _secondCount
    ) internal view returns (bytes memory input, bytes32 root) {
        bytes memory firstRefs = new bytes(_firstCount * 32);
        bytes memory secondRefs = new bytes(_secondCount * 32);
        (bytes memory firstInput, , bytes32 firstCommitment) = _syscoinEdgeDARefsInput(l2ChainId, 7, firstRefs);
        (bytes memory secondInput, , bytes32 secondCommitment) = _syscoinEdgeDARefsInput(l2ChainId + 1, 8, secondRefs);
        input = abi.encodePacked(firstInput, secondInput);

        bytes32 firstRefHash = keccak256(
            abi.encodePacked(
                SYSCOIN_EDGE_DA_REFS_DOMAIN,
                l2ChainId,
                uint256(7),
                firstCommitment,
                _firstCount,
                firstRefs
            )
        );
        bytes32 secondRefHash = keccak256(
            abi.encodePacked(
                SYSCOIN_EDGE_DA_REFS_DOMAIN,
                l2ChainId + 1,
                uint256(8),
                secondCommitment,
                _secondCount,
                secondRefs
            )
        );
        root = keccak256(abi.encodePacked(keccak256(abi.encodePacked(bytes32(0), firstRefHash)), secondRefHash));
    }

    function test_SyscoinEdgeDARefsCommitAndBindFinalV8BatchOutput() public {
        vm.etch(SYSCOIN_BITCOIN_DA_PRECOMPILE, address(new SyscoinBitcoinDAEcho()).code);
        bytes memory refs = abi.encodePacked(bytes32(uint256(11)), bytes32(uint256(22)));
        (bytes memory input, bytes32 root, ) = _syscoinEdgeDARefsInput(l2ChainId, 7, refs);

        vm.recordLogs();
        _commitSyscoinWithEdgeRefs(input, root, "");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 expectedCommitment = keccak256(
            abi.encodePacked(
                newCommitBatchInfoZKsyncOS.firstBlockTimestamp,
                newCommitBatchInfoZKsyncOS.lastBlockTimestamp,
                uint256(SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME),
                keccak256(abi.encodePacked(SYSCOIN_TEST_BATCH_DA_REF)),
                newCommitBatchInfoZKsyncOS.numberOfLayer1Txs,
                newCommitBatchInfoZKsyncOS.numberOfLayer2Txs,
                newCommitBatchInfoZKsyncOS.priorityOperationsHash,
                newCommitBatchInfoZKsyncOS.l2LogsTreeRoot,
                bytes32(0),
                newCommitBatchInfoZKsyncOS.dependencyRootsRollingHash,
                block.chainid,
                root
            )
        );

        bytes32 signature = keccak256("BlockCommit(uint256,bytes32,bytes32)");
        bool found;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(committer) && logs[i].topics.length == 4 && logs[i].topics[0] == signature) {
                assertEq(logs[i].topics[3], expectedCommitment);
                found = true;
            }
        }
        assertTrue(found, "BlockCommit not found");
    }

    function test_SyscoinEdgeDARefsAcceptExactAggregateLimitSplitAcrossMessages() public {
        vm.etch(SYSCOIN_BITCOIN_DA_PRECOMPILE, address(new SyscoinBitcoinDAEcho()).code);
        (bytes memory input, bytes32 root) = _splitSyscoinEdgeDARefs(16, 16);

        _commitSyscoinWithEdgeRefs(input, root, "");
    }

    function test_RevertWhenSyscoinEdgeDARefsExceedAggregateLimitAcrossMessages() public {
        (bytes memory input, bytes32 root) = _splitSyscoinEdgeDARefs(16, 17);
        uint256 secondMessageOffset = abi
            .encode(uint8(1), l2ChainId, uint256(7), bytes32(0), new bytes(16 * 32))
            .length;

        _commitSyscoinWithEdgeRefs(
            input,
            root,
            abi.encodeWithSelector(SyscoinEdgeDARefInputMalformed.selector, secondMessageOffset)
        );
    }

    function test_RevertWhenSingleSyscoinEdgeDARefMessageExceedsLimit() public {
        bytes memory refs = new bytes(33 * 32);
        (bytes memory input, bytes32 root, ) = _syscoinEdgeDARefsInput(l2ChainId, 7, refs);

        _commitSyscoinWithEdgeRefs(input, root, abi.encodeWithSelector(SyscoinEdgeDARefInputMalformed.selector, 0));
    }

    function test_SyscoinEdgeDARefsEmptyInputAndZeroRootRemainValid() public {
        _commitSyscoinWithEdgeRefs("", bytes32(0), "");
    }

    function test_RevertWhenSyscoinEdgeDARefsInputMalformed() public {
        _commitSyscoinWithEdgeRefs(
            hex"1234",
            bytes32(0),
            abi.encodeWithSelector(SyscoinEdgeDARefInputMalformed.selector, 0)
        );
    }

    function test_RevertWhenSyscoinEdgeDARefsEmptyButRootNonzero() public {
        bytes32 root = keccak256("nonzero");
        _commitSyscoinWithEdgeRefs(
            "",
            root,
            abi.encodeWithSelector(SyscoinEdgeDARefsRootMismatch.selector, root, bytes32(0))
        );
    }

    function test_RevertWhenSyscoinEdgeDARefsRootDoesNotOpen() public {
        vm.etch(SYSCOIN_BITCOIN_DA_PRECOMPILE, address(new SyscoinBitcoinDAEcho()).code);
        bytes memory refsA = abi.encodePacked(bytes32(uint256(11)));
        bytes memory refsB = abi.encodePacked(bytes32(uint256(22)));
        (, bytes32 rootA, ) = _syscoinEdgeDARefsInput(l2ChainId, 7, refsA);
        (bytes memory inputB, bytes32 rootB, ) = _syscoinEdgeDARefsInput(l2ChainId, 7, refsB);

        _commitSyscoinWithEdgeRefs(
            inputB,
            rootA,
            abi.encodeWithSelector(SyscoinEdgeDARefsRootMismatch.selector, rootA, rootB)
        );
    }

    function test_RevertWhenSyscoinEdgeDAEmbeddedCommitmentDoesNotMatchRefs() public {
        bytes memory refs = abi.encodePacked(bytes32(uint256(11)));
        (bytes memory input, bytes32 root, bytes32 actualCommitment) = _syscoinEdgeDARefsInput(l2ChainId, 7, refs);
        bytes32 embeddedCommitment = keccak256("wrong");
        assembly {
            mstore(add(input, 0x80), embeddedCommitment)
        }

        _commitSyscoinWithEdgeRefs(
            input,
            root,
            abi.encodeWithSelector(SyscoinEdgeDACommitmentMismatch.selector, embeddedCommitment, actualCommitment)
        );
    }

    function test_RevertWhenSyscoinBitcoinDAPrecompileReverts() public {
        vm.etch(SYSCOIN_BITCOIN_DA_PRECOMPILE, address(new SyscoinBitcoinDARevert()).code);
        bytes32 dataHash = bytes32(uint256(11));
        (bytes memory input, bytes32 root, ) = _syscoinEdgeDARefsInput(l2ChainId, 7, abi.encodePacked(dataHash));
        _commitSyscoinWithEdgeRefs(
            input,
            root,
            abi.encodeWithSelector(SyscoinEdgeDAPrecompileCallFailed.selector, dataHash)
        );
    }

    function test_RevertWhenSyscoinBitcoinDAReturnIsEmpty() public {
        vm.etch(SYSCOIN_BITCOIN_DA_PRECOMPILE, address(new SyscoinBitcoinDAEmpty()).code);
        bytes32 dataHash = bytes32(uint256(11));
        (bytes memory input, bytes32 root, ) = _syscoinEdgeDARefsInput(l2ChainId, 7, abi.encodePacked(dataHash));
        _commitSyscoinWithEdgeRefs(input, root, abi.encodeWithSelector(SyscoinEdgeDANotAvailable.selector, dataHash));
    }

    function test_RevertWhenSyscoinBitcoinDAReturnDoesNotEchoRawHash() public {
        vm.etch(SYSCOIN_BITCOIN_DA_PRECOMPILE, address(new SyscoinBitcoinDAWrong()).code);
        bytes32 dataHash = bytes32(uint256(11));
        (bytes memory input, bytes32 root, ) = _syscoinEdgeDARefsInput(l2ChainId, 7, abi.encodePacked(dataHash));
        _commitSyscoinWithEdgeRefs(input, root, abi.encodeWithSelector(SyscoinEdgeDANotAvailable.selector, dataHash));
    }
}
