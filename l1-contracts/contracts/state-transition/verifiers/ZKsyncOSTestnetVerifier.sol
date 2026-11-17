// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ZKsyncOSDualVerifier} from "./ZKsyncOSDualVerifier.sol";
import {IVerifierV2} from "../chain-interfaces/IVerifierV2.sol";
import {IVerifier} from "../chain-interfaces/IVerifier.sol";
import {InvalidMockProofLength, InvalidProof} from "../../common/L1ContractErrors.sol";
import {MAINNET_CHAIN_ID} from "../../common/Config.sol";
import {SYSCOIN_MAINNET_CHAIN_ID} from "../../common/SyscoinConfig.sol";

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice Explicit testnet-only verifier used by the server fake-prover pools.
/// @dev SYSCOIN: production deployments select ZKsyncOSDualVerifier; this subclass alone supports type 3.
contract ZKsyncOSTestnetVerifier is ZKsyncOSDualVerifier {
    constructor(
        IVerifierV2 _fflonkVerifier,
        IVerifier _plonkVerifier,
        address _initialOwner,
        uint256 _l1ChainId
    ) ZKsyncOSDualVerifier(_fflonkVerifier, _plonkVerifier, _initialOwner) {
        // SYSCOIN: on Gateway `block.chainid` is the Gateway chain, so carry the ultimate L1 identity
        // through deployment as well. Retaining the execution-chain check protects direct L1 deployments.
        assert(
            _l1ChainId != 0 &&
                _l1ChainId != MAINNET_CHAIN_ID &&
                _l1ChainId != SYSCOIN_MAINNET_CHAIN_ID &&
                block.chainid != MAINNET_CHAIN_ID &&
                block.chainid != SYSCOIN_MAINNET_CHAIN_ID
        );
    }

    /// @inheritdoc ZKsyncOSDualVerifier
    // solhint-disable-next-line func-name-mixedcase
    function IS_TESTNET_VERIFIER() external pure override returns (bool) {
        return true;
    }

    /// @dev Verifies the fake proof's public-input binding without checking a cryptographic proof.
    function mockVerify(uint256[] memory _publicInputs, uint256[] memory _proof) public pure override returns (bool) {
        if (_proof.length != 2) {
            revert InvalidMockProofLength();
        }
        if (_proof[0] != 13) {
            revert InvalidProof();
        }
        if (_proof[1] != _publicInputs[0]) {
            revert InvalidProof();
        }
        return true;
    }
}
