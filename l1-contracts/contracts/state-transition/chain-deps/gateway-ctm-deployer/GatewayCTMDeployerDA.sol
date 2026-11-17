// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

// SYSCOIN: Gateway binds its single-pair manager to the frozen universal-factory compact relay.
import {SyscoinRollupDAManager} from "../../data-availability/SyscoinRollupDAManager.sol";

import {
    SYSCOIN_EDGE_DA_RELAY_ADDRESS,
    SYSCOIN_EDGE_DA_RELAY_RUNTIME_HASH,
    SyscoinEdgeDARelayMissing,
    SyscoinEdgeDARelayCodeHashMismatch
} from "../../../common/SyscoinEdgeDARelayDeployment.sol";

import {SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME} from "../../../common/SyscoinConfig.sol";

import {DAContracts} from "contracts/common/StateTransitionTypes.sol";
import {GatewayDADeployerConfig} from "./GatewayCTMDeployer.sol";

/// @title GatewayCTMDeployerDA
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice Gateway CTM DA deployer for the canonical Syscoin compact relay.
/// @dev SYSCOIN: ABI-reserved DA result slots remain zero; Validium is never deployed.
contract GatewayCTMDeployerDA {
    DAContracts internal deployedResult;

    /// @notice Returns the deployed contracts from this deployer.
    /// @return result The struct with information about the deployed contracts.
    function getResult() external view returns (DAContracts memory result) {
        result = deployedResult;
    }

    constructor(GatewayDADeployerConfig memory _config) {
        DAContracts memory result;

        // SYSCOIN: The relay must already exist at the address baked into the guest/server. Verify
        // exact runtime identity before the manager can make it settlement-authoritative.
        address relay = SYSCOIN_EDGE_DA_RELAY_ADDRESS;
        if (relay.code.length == 0) {
            revert SyscoinEdgeDARelayMissing(relay);
        }
        bytes32 actualRelayCodeHash;
        assembly {
            actualRelayCodeHash := extcodehash(relay)
        }
        if (actualRelayCodeHash != SYSCOIN_EDGE_DA_RELAY_RUNTIME_HASH) {
            revert SyscoinEdgeDARelayCodeHashMismatch(relay, SYSCOIN_EDGE_DA_RELAY_RUNTIME_HASH, actualRelayCodeHash);
        }

        result.rollupSLDAValidator = relay;
        SyscoinRollupDAManager rollupDAManager = new SyscoinRollupDAManager{salt: _config.salt}(relay);
        rollupDAManager.updateDAPair(result.rollupSLDAValidator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME, true);
        // Note, that the governance still has to accept it.
        // It will happen in a separate voting after the deployment is done.
        rollupDAManager.transferOwnership(_config.aliasedGovernanceAddress);
        result.rollupDAManager = address(rollupDAManager);

        deployedResult = result;
    }
}
