// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {UnknownVerifierVersion} from "../L1StateTransitionErrors.sol";
import {IVerifierV2} from "../chain-interfaces/IVerifierV2.sol";
import {IVerifier} from "../chain-interfaces/IVerifier.sol";
import {
    // SYSCOIN: constructor/rotation now reject non-contract verifiers and no add/remove selector remains.
    AddressHasNoCode,
    EmptyProofLength,
    UnknownVerifierType,
    MockVerifierNotSupported,
    InvalidProofFormat,
    ZeroAddress,
    EmptyPublicInputsLength
} from "../../common/L1ContractErrors.sol";
import {IZKsyncOSDualVerifier} from "../chain-interfaces/IZKsyncOSDualVerifier.sol";
import {PUBLIC_INPUT_SHIFT} from "../../common/Config.sol";
import {Ownable2Step} from "@openzeppelin/contracts-v4/access/Ownable2Step.sol";

error NonZeroCarriedHash();

/// @title ZKsync OS Dual Verifier
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice SYSCOIN: This contract preserves the pinned upstream dual-verifier deployment surface while routing
/// zk-SNARK proof verification exclusively to the canonical ZKsync OS PLONK verifier.
/// It reuses the same interface as on the original `Verifier` contract, while abusing one of the fields
/// (`_recursiveAggregationInput`) for proof verification type.
contract ZKsyncOSDualVerifier is Ownable2Step, IVerifier, IZKsyncOSDualVerifier {
    /// @dev Type of verification for ZKsync OS PLONK verifier.
    uint256 internal constant ZKSYNC_OS_PLONK_VERIFICATION_TYPE = 2;

    /// @dev Proof-skipping verifier type, supported only by the explicit testnet subclass.
    uint256 internal constant ZKSYNC_OS_MOCK_VERIFICATION_TYPE = 3;

    // SYSCOIN: fresh v0.4 deployments use the V8 proof-header version, not upstream's provisional slot.
    uint32 internal constant CANONICAL_ZKSYNC_OS_VERIFIER_VERSION = 8;

    /// @notice Mapping of different FFLONK verifiers dependent on their version.
    /// @dev SYSCOIN: retained for exact pinned-upstream artifact, deployment, and introspection
    /// compatibility. No production proof type routes to this dormant verifier.
    mapping(uint32 => IVerifierV2) public fflonkVerifiers;

    /// @notice Mapping of different PLONK verifiers dependent on their version.
    /// @dev SYSCOIN: only canonical slot 8 may be populated or owner-rotated.
    mapping(uint32 => IVerifier) public plonkVerifiers;

    /// @notice Emitted when governance atomically rotates the active PLONK verifier.
    event VerifierReplaced(uint32 indexed version, address indexed oldVerifier, address indexed newVerifier);

    /// @param _fflonkVerifier The dormant, pinned-upstream FFLONK verifier contract.
    /// @param _plonkVerifier The address of the PLONK verifier contract.
    /// @param _initialOwner The initial owner governing verifier-version rotation.
    constructor(IVerifierV2 _fflonkVerifier, IVerifier _plonkVerifier, address _initialOwner) {
        // SYSCOIN: fail closed at deployment; both advertised implementations must be contracts,
        // while only PLONK is reachable from the consensus proof router.
        _requireContract(address(_fflonkVerifier));
        _requireContract(address(_plonkVerifier));
        require(_initialOwner != address(0), ZeroAddress());
        fflonkVerifiers[CANONICAL_ZKSYNC_OS_VERIFIER_VERSION] = _fflonkVerifier;
        plonkVerifiers[CANONICAL_ZKSYNC_OS_VERIFIER_VERSION] = _plonkVerifier;
        _transferOwnership(_initialOwner);
    }

    /// @notice Atomically rotates the active PLONK verifier without exposing an empty proof-verifier slot.
    /// @dev SYSCOIN: replaces upstream's independently callable add/remove pair, whose remove-first path
    /// can halt proof settlement. The dormant FFLONK compatibility artifact is intentionally unchanged.
    function replaceVerifier(uint32 version, IVerifier newPlonkVerifier) external override onlyOwner {
        if (version != CANONICAL_ZKSYNC_OS_VERIFIER_VERSION) {
            revert UnknownVerifierVersion();
        }
        _requireContract(address(newPlonkVerifier));
        address oldVerifier = address(plonkVerifiers[version]);
        plonkVerifiers[version] = newPlonkVerifier;
        emit VerifierReplaced(version, oldVerifier, address(newPlonkVerifier));
    }

    /// @notice Routes zk-SNARK proof verification to the appropriate verifier based on the proof type.
    /// @param _publicInputs The public inputs to the proof.
    /// @param _proof The zk-SNARK proof itself.
    /// @dev  The first element of the `_proof` determines the verifier type.
    ///     - 2 indicates the sole canonical ZKsync OS PLONK verifier.
    ///     - 3 delegates to `mockVerify`, which production rejects and only the testnet subclass overrides.
    ///     - Every other type is rejected.
    /// @return Returns `true` if the proof verification succeeds, otherwise throws an error.
    function verify(uint256[] calldata _publicInputs, uint256[] calldata _proof) public view virtual returns (bool) {
        // Ensure the proof has a valid length (at least one element
        // for the proof system differentiator).
        if (_proof.length == 0) {
            revert EmptyProofLength();
        }

        // Ensure public inputs are not empty for clarity.
        if (_publicInputs.length == 0) {
            revert EmptyPublicInputsLength();
        }

        // The first element of `_proof` determines the verifier type.
        uint256 verifierType = _proof[0] & 255;
        uint32 verifierVersion = uint32(_proof[0] >> 8);

        // SYSCOIN: only the server's canonical V8 proof header (0x802/0x803) may select a verifier.
        if (verifierVersion != CANONICAL_ZKSYNC_OS_VERIFIER_VERSION) {
            revert UnknownVerifierVersion();
        }

        // Validate that unused bits (40-255) are zero.
        if (_proof[0] >> 40 != 0) {
            revert InvalidProofFormat();
        }

        if (plonkVerifiers[verifierVersion] == IVerifier(address(0))) {
            revert UnknownVerifierVersion();
        }

        if (verifierType == ZKSYNC_OS_PLONK_VERIFICATION_TYPE) {
            uint256[] memory args = new uint256[](1);
            args[0] = computeZKsyncOSHash(_proof[1], _publicInputs);

            return plonkVerifiers[verifierVersion].verify(args, _extractZKsyncOSProof(_proof));
        } else if (verifierType == ZKSYNC_OS_MOCK_VERIFICATION_TYPE) {
            uint256[] memory args = new uint256[](1);
            args[0] = computeZKsyncOSHash(_proof[1], _publicInputs);

            return mockVerify(args, _extractZKsyncOSProof(_proof));
        } else {
            revert UnknownVerifierType();
        }
    }

    /// @dev Production fails closed; the explicit testnet subclass overrides this for fake proving.
    function mockVerify(uint256[] memory, uint256[] memory) public view virtual returns (bool) {
        revert MockVerifierNotSupported();
    }

    /// @notice Reports whether this wrapper deliberately accepts fake/type-3 proofs.
    /// @dev SYSCOIN: the server uses this explicit marker to bind prover mode to the deployed verifier.
    // solhint-disable-next-line func-name-mixedcase
    function IS_TESTNET_VERIFIER() external pure virtual override returns (bool) {
        return false;
    }

    /// @inheritdoc IVerifier
    /// @dev Returns the sole canonical V8 PLONK verification key hash.
    function verificationKeyHash() external view returns (bytes32) {
        return plonkVerifiers[CANONICAL_ZKSYNC_OS_VERIFIER_VERSION].verificationKeyHash();
    }

    /// @notice Calculates a keccak256 hash of the runtime loaded verification keys from the selected verifier.
    /// @return The keccak256 hash of the loaded verification keys based on the verifier.
    function verificationKeyHash(uint256 _verifierType) external view returns (bytes32) {
        uint256 verifierType = _verifierType & 255;
        uint32 verifierVersion = uint32(_verifierType >> 8);

        // SYSCOIN: key-hash introspection must use the same canonical V8 selector as verification.
        if (verifierVersion != CANONICAL_ZKSYNC_OS_VERIFIER_VERSION) {
            revert UnknownVerifierVersion();
        }

        // Validate that unused bits (40-255) are zero.
        if (_verifierType >> 40 != 0) {
            revert InvalidProofFormat();
        }

        if (plonkVerifiers[verifierVersion] == IVerifier(address(0))) {
            revert UnknownVerifierVersion();
        }

        if (verifierType == ZKSYNC_OS_PLONK_VERIFICATION_TYPE) {
            return plonkVerifiers[verifierVersion].verificationKeyHash();
        }
        // If the verifier type is unknown, revert with an error.
        else {
            revert UnknownVerifierType();
        }
    }

    /// @dev SYSCOIN: shared constructor/rotation validation avoids advertising EOAs as verifiers.
    function _requireContract(address _verifier) private view {
        require(_verifier != address(0), ZeroAddress());
        if (_verifier.code.length == 0) {
            revert AddressHasNoCode(_verifier);
        }
    }

    function _extractZKsyncOSProof(uint256[] calldata _proof) internal pure returns (uint256[] memory result) {
        uint256 resultLength = _proof.length - 1 - 1;

        // Allocate memory for the new array (_proof.length - 1) since the first element is omitted.
        result = new uint256[](resultLength);

        // Copy elements starting from index 1 (the second element) of the original array.
        assembly {
            calldatacopy(add(result, 0x20), add(_proof.offset, 0x40), mul(resultLength, 0x20))
        }
    }

    function computeZKsyncOSHash(
        uint256 initialHash,
        uint256[] calldata _publicInputs
    ) public pure returns (uint256 result) {
        // The prover hashes the concatenation of all per-batch hashes ONCE, then truncates:
        //   N == 1: H_1                         (no hash)
        //   N >= 2: keccak(H_1 || ... || H_N)
        // A rolling fold (`keccak(keccak(H_1, H_2), H_3)`) coincides for N <= 2 but diverges
        // from N == 3 on, so it must not be used here.
        // The carried hash (`_proof[1]`) is a pre-V8 OhBender concept; the V8 unified layer
        // has no continuation input, so no proof for a non-zero carry can exist. The wire
        // slot is kept as reserved, must-be-zero.
        if (initialHash != 0) {
            revert NonZeroCarriedHash();
        }
        result = _publicInputs.length == 1 ? _publicInputs[0] : uint256(keccak256(abi.encodePacked(_publicInputs)));
        result = result >> PUBLIC_INPUT_SHIFT;
    }
}
