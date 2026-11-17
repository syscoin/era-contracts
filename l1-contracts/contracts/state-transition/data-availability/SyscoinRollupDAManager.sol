// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {L2DACommitmentScheme} from "../../common/Config.sol";
import {ZeroAddress} from "../../common/L1ContractErrors.sol";
import {SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME} from "../../common/SyscoinConfig.sol";
import {RollupDAManager} from "./RollupDAManager.sol";

// SYSCOIN: Surface the exact immutable-pair mismatch instead of using mutable string reverts.
error SyscoinL1DAValidatorMismatch(address expected, address actual);
error SyscoinL2DACommitmentSchemeMismatch(L2DACommitmentScheme expected, L2DACommitmentScheme actual);

/// @notice Rollup DA manager restricted to one Syscoin compact validator/scheme pair.
/// @dev SYSCOIN: Governance may disable or re-enable the canonical pair, but cannot authorize
///      another validator or commitment scheme.
contract SyscoinRollupDAManager is RollupDAManager {
    address public immutable SYSCOIN_L1_DA_VALIDATOR;

    // SYSCOIN: Pin the only validator at construction so ownership cannot broaden the DA trust model.
    constructor(address _syscoinL1DAValidator) {
        if (_syscoinL1DAValidator == address(0)) {
            revert ZeroAddress();
        }
        SYSCOIN_L1_DA_VALIDATOR = _syscoinL1DAValidator;
        isAllowedDAConfiguration[_syscoinL1DAValidator][SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME] = true;
        emit DAPairUpdated(_syscoinL1DAValidator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME, true);
    }

    // SYSCOIN: Preserve the upstream governance switch while rejecting every non-canonical pair.
    function updateDAPair(
        address _l1DAValidator,
        L2DACommitmentScheme _l2DACommitmentScheme,
        bool _status
    ) external override onlyOwner validDAConfiguration(_l1DAValidator, _l2DACommitmentScheme) {
        if (_l1DAValidator != SYSCOIN_L1_DA_VALIDATOR) {
            revert SyscoinL1DAValidatorMismatch(SYSCOIN_L1_DA_VALIDATOR, _l1DAValidator);
        }
        if (_l2DACommitmentScheme != SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME) {
            revert SyscoinL2DACommitmentSchemeMismatch(SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME, _l2DACommitmentScheme);
        }
        isAllowedDAConfiguration[_l1DAValidator][_l2DACommitmentScheme] = _status;
        emit DAPairUpdated(_l1DAValidator, _l2DACommitmentScheme, _status);
    }
}
