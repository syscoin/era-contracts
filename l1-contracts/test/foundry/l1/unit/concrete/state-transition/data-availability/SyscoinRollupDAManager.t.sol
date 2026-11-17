// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {L2DACommitmentScheme} from "contracts/common/Config.sol";
import {ZeroAddress} from "contracts/common/L1ContractErrors.sol";
import {SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME} from "contracts/common/SyscoinConfig.sol";
import {
    SyscoinRollupDAManager,
    SyscoinL1DAValidatorMismatch,
    SyscoinL2DACommitmentSchemeMismatch
} from "contracts/state-transition/data-availability/SyscoinRollupDAManager.sol";
import {DeployCTMScript} from "deploy-scripts/ctm/DeployCTM.s.sol";

/// @dev SYSCOIN: Verifies CTM constructor binding and the single allowed compact-DA pair.
contract SyscoinDeployCTMCalldataHarness is DeployCTMScript {
    function setSyscoinValidator(address _validator) external {
        ctmAddresses.daAddresses.daContracts.rollupSLDAValidator = _validator;
    }

    function syscoinManagerConstructorArgs() external view returns (bytes memory) {
        return getCreationCalldata("SyscoinRollupDAManager", false);
    }
}

contract SyscoinRollupDAManagerTest is Test {
    address internal validator;
    SyscoinRollupDAManager internal manager;

    function setUp() public {
        validator = makeAddr("syscoin-validator");
        manager = new SyscoinRollupDAManager(validator);
    }

    function test_ConstructorRegistersOnlyCanonicalPair() public {
        assertTrue(manager.isPairAllowed(validator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME));
        assertFalse(manager.isPairAllowed(validator, L2DACommitmentScheme.BLOBS_AND_PUBDATA_KECCAK256));
        assertFalse(manager.isPairAllowed(makeAddr("other-validator"), SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME));
    }

    function test_RevertWhenConstructorValidatorIsZero() public {
        vm.expectRevert(ZeroAddress.selector);
        new SyscoinRollupDAManager(address(0));
    }

    function test_RevertWhenAuthorizingAnotherValidator() public {
        address otherValidator = makeAddr("other-validator");
        vm.expectRevert(abi.encodeWithSelector(SyscoinL1DAValidatorMismatch.selector, validator, otherValidator));
        manager.updateDAPair(otherValidator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME, true);
    }

    function test_RevertWhenAuthorizingAnotherScheme() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SyscoinL2DACommitmentSchemeMismatch.selector,
                SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME,
                L2DACommitmentScheme.BLOBS_AND_PUBDATA_KECCAK256
            )
        );
        manager.updateDAPair(validator, L2DACommitmentScheme.BLOBS_AND_PUBDATA_KECCAK256, true);
    }

    function test_GovernanceCanOnlyToggleCanonicalPair() public {
        manager.updateDAPair(validator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME, false);
        assertFalse(manager.isPairAllowed(validator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME));

        manager.updateDAPair(validator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME, true);
        assertTrue(manager.isPairAllowed(validator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME));
    }

    function test_DirectDeploymentEncodesCanonicalValidator() public {
        SyscoinDeployCTMCalldataHarness harness = new SyscoinDeployCTMCalldataHarness();
        harness.setSyscoinValidator(validator);

        address encodedValidator = abi.decode(harness.syscoinManagerConstructorArgs(), (address));
        assertEq(encodedValidator, validator);
    }
}
