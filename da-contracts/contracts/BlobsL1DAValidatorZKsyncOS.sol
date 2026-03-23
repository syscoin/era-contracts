// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IL1DAValidator, L1DAValidatorOutput} from "./IL1DAValidator.sol";

import {
    BitcoinDAPrecompileCallFailed,
    BitcoinDAVerificationFailed,
    InvalidBlobsPublished,
    InvalidBlobsDAInputLength
} from "./DAContractsErrors.sol";

/// @title L1 DA validator for ZKsync OS “blobs” commitment on non–EIP-4844 L1 (e.g. Syscoin NEVM).
/// @dev No `blobhash` opcode and no `publishBlobs` / prepublish flow. The operator passes the full list of
/// 32-byte DA commitment hashes in `operatorDAInput`; each is checked with the Syscoin Bitcoin DA precompile,
/// then `keccak256(operatorDAInput)` must match the L2 DA commitment (same encoding as ZKsync OS blob mode).
contract BlobsL1DAValidatorZKsyncOS is IL1DAValidator {
    /// @dev Same Bitcoin DA precompile as `RollupL1DAValidator` on this fork.
    address internal constant BITCOINDA_PRECOMPILE_ADDR = address(0x63);
    uint16 internal constant BITCOINDA_PRECOMPILE_COST = 1400;

    uint256 private constant WORD = 32;

    /// @inheritdoc IL1DAValidator
    function checkDA(
        uint256, // _chainId
        uint256, // _batchNumber
        bytes32 _l2DAValidatorOutputHash,
        bytes calldata _operatorDAInput,
        uint256 // _maxBlobsSupported
    ) external view returns (L1DAValidatorOutput memory output) {
        uint256 len = _operatorDAInput.length;
        if (len == 0 || len % WORD != 0) {
            revert InvalidBlobsDAInputLength(len);
        }

        for (uint256 i = 0; i < len; i += WORD) {
            _verifyBitcoinDA(bytes32(_operatorDAInput[i:i + WORD]));
        }

        bytes32 publishedHash = keccak256(_operatorDAInput);
        if (publishedHash != _l2DAValidatorOutputHash) {
            revert InvalidBlobsPublished(publishedHash, _l2DAValidatorOutputHash);
        }

        output.stateDiffHash = bytes32(0);
        output.blobsLinearHashes = new bytes32[](0);
        output.blobsOpeningCommitments = new bytes32[](0);
    }

    /// @dev Same pattern as `RollupL1DAValidator._verifyBitcoinDA`.
    function _verifyBitcoinDA(bytes32 _dataHash) internal view {
        (bool success, bytes memory result) = BITCOINDA_PRECOMPILE_ADDR.staticcall{gas: BITCOINDA_PRECOMPILE_COST}(
            abi.encode(_dataHash)
        );

        if (!success) {
            revert BitcoinDAPrecompileCallFailed();
        }
        if (result.length == 0) {
            revert BitcoinDAVerificationFailed();
        }
    }
}
