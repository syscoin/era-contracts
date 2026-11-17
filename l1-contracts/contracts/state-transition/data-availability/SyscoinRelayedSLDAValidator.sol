// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IL1DAValidator, L1DAValidatorOutput} from "../chain-interfaces/IL1DAValidator.sol";
import {IL2Bridgehub} from "../../core/bridgehub/IL2Bridgehub.sol";
import {L2_BRIDGEHUB_ADDR, L2_TO_L1_MESSENGER_SYSTEM_CONTRACT} from "../../common/l2-helpers/L2ContractInterfaces.sol";
import {
    SYSCOIN_RELAYED_EDGE_DA_VALIDATOR_VERSION,
    SYSCOIN_DA_REFERENCE_SIZE,
    SYSCOIN_DA_MAX_REFS_PER_BATCH
} from "../../common/SyscoinConfig.sol";
import {
    L1DAValidatorInvalidSender,
    SyscoinEdgeDACommitmentMismatch,
    SyscoinEdgeDARefInputMalformed
} from "../L1StateTransitionErrors.sol";

/// @notice Canonical Gateway relay for compact ordered Syscoin Bitcoin-DA hash references.
/// @dev SYSCOIN: Only the registered edge chain may publish a bounded commitment-opening message.
contract SyscoinRelayedSLDAValidator is IL1DAValidator {
    // SYSCOIN: Authenticate the message against Gateway's canonical Bridgehub chain registration.
    function _ensureOnlyChainSender(uint256 _chainId) internal view {
        if (IL2Bridgehub(L2_BRIDGEHUB_ADDR).getZKChain(_chainId) != msg.sender) {
            revert L1DAValidatorInvalidSender(msg.sender);
        }
    }

    function checkDA(
        uint256 _chainId,
        uint256 _batchNumber,
        bytes32 _l2DAValidatorOutputHash,
        bytes calldata _operatorDAInput,
        uint256
    ) external returns (L1DAValidatorOutput memory output) {
        _ensureOnlyChainSender(_chainId);

        // SYSCOIN: Relay only a non-empty, bounded sequence of complete compact references.
        uint256 inputLength = _operatorDAInput.length;
        if (
            inputLength == 0 ||
            inputLength % SYSCOIN_DA_REFERENCE_SIZE != 0 ||
            inputLength / SYSCOIN_DA_REFERENCE_SIZE > SYSCOIN_DA_MAX_REFS_PER_BATCH
        ) {
            revert SyscoinEdgeDARefInputMalformed(0);
        }

        bytes32 actualCommitment = keccak256(_operatorDAInput);
        if (actualCommitment != _l2DAValidatorOutputHash) {
            revert SyscoinEdgeDACommitmentMismatch(_l2DAValidatorOutputHash, actualCommitment);
        }

        output.blobsLinearHashes = new bytes32[](0);
        output.blobsOpeningCommitments = new bytes32[](0);

        // SYSCOIN: Commit the versioned chain/batch envelope to final L1 through the canonical messenger.
        // slither-disable-next-line unused-return
        L2_TO_L1_MESSENGER_SYSTEM_CONTRACT.sendToL1(
            abi.encode(
                SYSCOIN_RELAYED_EDGE_DA_VALIDATOR_VERSION,
                _chainId,
                _batchNumber,
                _l2DAValidatorOutputHash,
                _operatorDAInput
            )
        );
    }
}
