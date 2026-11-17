// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IL1DAValidator, L1DAValidatorOutput} from "./IL1DAValidator.sol";
import {
    BitcoinDAPrecompileCallFailed,
    BitcoinDAVerificationFailed,
    InvalidBlobsDAInputLength,
    InvalidBlobsPublished
} from "./DAContractsErrors.sol";
import {
    SYSCOIN_BITCOIN_DA_PRECOMPILE_ADDRESS,
    SYSCOIN_BITCOIN_DA_PRECOMPILE_GAS,
    SYSCOIN_DA_MAX_BLOBS_PER_BATCH,
    SYSCOIN_DA_REFERENCE_SIZE
} from "./SyscoinDAUtils.sol";

/// @title L1 DA validator for compact ZKsync OS commitments on Syscoin NEVM.
/// @dev SYSCOIN: The operator supplies ordered 32-byte Bitcoin DA identifiers. Each identifier must be available through
/// Syscoin's raw data-hash precompile, and their packed encoding must open the commitment emitted by ZKsync OS.
contract SyscoinL1DAValidatorZKsyncOS is IL1DAValidator {
    /// @inheritdoc IL1DAValidator
    function checkDA(
        uint256, // _chainId
        uint256, // _batchNumber
        bytes32 _l2DAValidatorOutputHash,
        bytes calldata _operatorDAInput,
        uint256 // _maxBlobsSupported
    ) external returns (L1DAValidatorOutput memory output) {
        // SYSCOIN: Accept only a bounded, non-empty sequence of complete compact references.
        uint256 inputLength = _operatorDAInput.length;
        if (
            inputLength == 0 ||
            inputLength % SYSCOIN_DA_REFERENCE_SIZE != 0 ||
            inputLength / SYSCOIN_DA_REFERENCE_SIZE > SYSCOIN_DA_MAX_BLOBS_PER_BATCH
        ) {
            revert InvalidBlobsDAInputLength(inputLength);
        }

        for (uint256 offset = 0; offset < inputLength; offset += SYSCOIN_DA_REFERENCE_SIZE) {
            _verifyBitcoinDA(bytes32(_operatorDAInput[offset:offset + SYSCOIN_DA_REFERENCE_SIZE]));
        }

        bytes32 publishedHash = keccak256(_operatorDAInput);
        if (publishedHash != _l2DAValidatorOutputHash) {
            revert InvalidBlobsPublished(publishedHash, _l2DAValidatorOutputHash);
        }

        output.stateDiffHash = bytes32(0);
        output.blobsLinearHashes = new bytes32[](0);
        output.blobsOpeningCommitments = new bytes32[](0);
    }

    function _verifyBitcoinDA(bytes32 _dataHash) internal {
        // SYSCOIN: This fixed consensus precompile consumes a raw identifier
        // rather than selector-prefixed ABI calldata. Use a bounded raw call
        // on this already-stateful DA-validation path and fail closed.
        (bool success, bytes memory result) = SYSCOIN_BITCOIN_DA_PRECOMPILE_ADDRESS.call{
            gas: SYSCOIN_BITCOIN_DA_PRECOMPILE_GAS
        }(abi.encodePacked(_dataHash));

        if (!success) {
            revert BitcoinDAPrecompileCallFailed();
        }
        // SYSCOIN: Decode only after the exact-length guard; this avoids a truncating bytes-to-bytes32 cast.
        if (result.length != SYSCOIN_DA_REFERENCE_SIZE || abi.decode(result, (bytes32)) != _dataHash) {
            revert BitcoinDAVerificationFailed();
        }
    }
}
