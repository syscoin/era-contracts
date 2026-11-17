// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ZKsyncOSVerifierFflonk} from "../../verifiers/ZKsyncOSVerifierFflonk.sol";
import {ZKsyncOSVerifierPlonk} from "../../verifiers/ZKsyncOSVerifierPlonk.sol";
import {ZKsyncOSDualVerifier} from "../../verifiers/ZKsyncOSDualVerifier.sol";
import {ZKsyncOSTestnetVerifier} from "../../verifiers/ZKsyncOSTestnetVerifier.sol";

import {IVerifier} from "../../chain-interfaces/IVerifier.sol";
import {IVerifierV2} from "../../chain-interfaces/IVerifierV2.sol";

import {WrongCTMDeployerVariant} from "../../../common/L1ContractErrors.sol";

import {Verifiers} from "contracts/common/StateTransitionTypes.sol";
import {GatewayVerifiersDeployerConfig} from "./GatewayCTMDeployer.sol";

/// @title GatewayCTMDeployerVerifiersZKsyncOS
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice Gateway CTM ZKsyncOS Verifiers deployer: deploys ZKsyncOS verifier contracts.
/// @dev Deploys the pinned-upstream FFLONK compatibility artifact, the active PLONK verifier,
/// and either the production or explicit testnet wrapper. SYSCOIN: proof routing remains PLONK-only.
/// For Era verifiers, use GatewayCTMDeployerVerifiers instead.
/// This contract is expected to be deployed via the built-in L2 `Create2Factory`.
contract GatewayCTMDeployerVerifiersZKsyncOS {
    Verifiers internal deployedResult;

    /// @notice Returns the deployed contracts from this deployer.
    /// @return result The struct with information about the deployed contracts.
    function getResult() external view returns (Verifiers memory result) {
        result = deployedResult;
    }

    /// @dev SYSCOIN: `_l1ChainId` remains the ultimate base-layer identity when this executes on Gateway.
    constructor(GatewayVerifiersDeployerConfig memory _config, uint256 _l1ChainId) {
        if (!_config.isZKsyncOS) {
            revert WrongCTMDeployerVariant();
        }
        bytes32 salt = _config.salt;

        Verifiers memory result;

        // SYSCOIN: retain the pinned-upstream dormant artifact and deployment result for minimal
        // lineage drift; ZKsyncOSDualVerifier has no proof-type branch that can execute it.
        result.verifierFflonk = address(new ZKsyncOSVerifierFflonk{salt: salt}());
        result.verifierPlonk = address(new ZKsyncOSVerifierPlonk{salt: salt}());

        // SYSCOIN: production routes only PLONK; today's explicitly configured testnet retains
        // type-3 fake-proof verification until the real app-bound VK is activated.
        result.verifier = _config.testnetVerifier
            ? address(
                new ZKsyncOSTestnetVerifier{salt: salt}(
                    IVerifierV2(result.verifierFflonk),
                    IVerifier(result.verifierPlonk),
                    _config.aliasedGovernanceAddress,
                    _l1ChainId
                )
            )
            : address(
                new ZKsyncOSDualVerifier{salt: salt}(
                    IVerifierV2(result.verifierFflonk),
                    IVerifier(result.verifierPlonk),
                    _config.aliasedGovernanceAddress
                )
            );

        deployedResult = result;
    }
}
