// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {IVerifierV2} from "./IVerifierV2.sol";
import {IVerifier} from "./IVerifier.sol";

/// @notice SYSCOIN: Interface for zkOS slot-8 verifier getters and governed PLONK rotation.
interface IZKsyncOSDualVerifier {
    function fflonkVerifiers(uint32 version) external view returns (IVerifierV2);
    function plonkVerifiers(uint32 version) external view returns (IVerifier);

    // SYSCOIN: only the active PLONK verifier is rotatable; the retained upstream FFLONK
    // artifact is deployment-compatible but deliberately absent from the proof router.
    function replaceVerifier(uint32 version, IVerifier newPlonkVerifier) external;

    /// @notice Explicitly binds server fake/real prover mode to the deployed wrapper.
    function IS_TESTNET_VERIFIER() external view returns (bool);
}
