// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DAContracts} from "contracts/common/StateTransitionTypes.sol";
import {L2DACommitmentScheme} from "contracts/common/Config.sol";
import {SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME} from "contracts/common/SyscoinConfig.sol";
import {
    SYSCOIN_EDGE_DA_RELAY_ADDRESS,
    SYSCOIN_EDGE_DA_RELAY_FACTORY,
    SYSCOIN_EDGE_DA_RELAY_FACTORY_RUNTIME_HASH,
    SYSCOIN_EDGE_DA_RELAY_SALT,
    SYSCOIN_EDGE_DA_RELAY_INIT_CODE_HASH,
    SYSCOIN_EDGE_DA_RELAY_RUNTIME_HASH,
    SyscoinEdgeDARelayMissing,
    SyscoinEdgeDARelayCodeHashMismatch
} from "contracts/common/SyscoinEdgeDARelayDeployment.sol";
import {Utils} from "deploy-scripts/utils/Utils.sol";
import {GatewayDADeployerConfig} from "contracts/state-transition/chain-deps/gateway-ctm-deployer/GatewayCTMDeployer.sol";
import {GatewayCTMDeployerDA} from "contracts/state-transition/chain-deps/gateway-ctm-deployer/GatewayCTMDeployerDA.sol";
import {
    SyscoinRollupDAManager,
    SyscoinL1DAValidatorMismatch,
    SyscoinL2DACommitmentSchemeMismatch
} from "contracts/state-transition/data-availability/SyscoinRollupDAManager.sol";
import {SyscoinRelayedSLDAValidator} from "contracts/state-transition/data-availability/SyscoinRelayedSLDAValidator.sol";

contract SyscoinGatewayCTMDeployerDATest is Test {
    function _config() private pure returns (GatewayDADeployerConfig memory) {
        return
            GatewayDADeployerConfig({salt: keccak256("syscoin-gateway-da"), aliasedGovernanceAddress: address(0x1234)});
    }

    function _etchCanonicalRelay() private {
        vm.etch(SYSCOIN_EDGE_DA_RELAY_ADDRESS, type(SyscoinRelayedSLDAValidator).runtimeCode);
        assertEq(SYSCOIN_EDGE_DA_RELAY_ADDRESS.codehash, SYSCOIN_EDGE_DA_RELAY_RUNTIME_HASH);
    }

    function test_SyscoinGatewayRegistersOnlyCompactPair() public {
        _etchCanonicalRelay();

        GatewayCTMDeployerDA deployer = new GatewayCTMDeployerDA(_config());
        DAContracts memory deployed = deployer.getResult();
        SyscoinRollupDAManager manager = SyscoinRollupDAManager(deployed.rollupDAManager);

        assertGt(deployed.rollupSLDAValidator.code.length, 0);
        assertEq(deployed.validiumDAValidator, address(0));
        assertEq(manager.SYSCOIN_L1_DA_VALIDATOR(), deployed.rollupSLDAValidator);
        assertTrue(manager.isPairAllowed(deployed.rollupSLDAValidator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME));
        assertFalse(
            manager.isPairAllowed(deployed.rollupSLDAValidator, L2DACommitmentScheme.BLOBS_AND_PUBDATA_KECCAK256)
        );

        address otherValidator = makeAddr("other-validator");
        vm.expectRevert(
            abi.encodeWithSelector(SyscoinL1DAValidatorMismatch.selector, deployed.rollupSLDAValidator, otherValidator)
        );
        vm.prank(address(deployer));
        manager.updateDAPair(otherValidator, SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                SyscoinL2DACommitmentSchemeMismatch.selector,
                SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME,
                L2DACommitmentScheme.BLOBS_AND_PUBDATA_KECCAK256
            )
        );
        vm.prank(address(deployer));
        manager.updateDAPair(deployed.rollupSLDAValidator, L2DACommitmentScheme.BLOBS_AND_PUBDATA_KECCAK256, true);
    }

    function test_SyscoinCanonicalRelayManifestReproducesArtifactAndAddress() public view {
        // SYSCOIN: Freeze the exact factory, compiler artifact, runtime, salt, and CREATE2 address.
        assertEq(SYSCOIN_EDGE_DA_RELAY_FACTORY, Utils.DETERMINISTIC_CREATE2_ADDRESS);
        assertEq(keccak256(Utils.CREATE2_FACTORY_RUNTIME_BYTECODE), SYSCOIN_EDGE_DA_RELAY_FACTORY_RUNTIME_HASH);
        assertEq(keccak256(type(SyscoinRelayedSLDAValidator).creationCode), SYSCOIN_EDGE_DA_RELAY_INIT_CODE_HASH);
        assertEq(keccak256(type(SyscoinRelayedSLDAValidator).runtimeCode), SYSCOIN_EDGE_DA_RELAY_RUNTIME_HASH);
        assertEq(
            vm.computeCreate2Address(
                SYSCOIN_EDGE_DA_RELAY_SALT,
                SYSCOIN_EDGE_DA_RELAY_INIT_CODE_HASH,
                SYSCOIN_EDGE_DA_RELAY_FACTORY
            ),
            SYSCOIN_EDGE_DA_RELAY_ADDRESS
        );
    }

    function test_SyscoinGatewayRejectsMissingCanonicalRelay() public {
        vm.expectRevert(abi.encodeWithSelector(SyscoinEdgeDARelayMissing.selector, SYSCOIN_EDGE_DA_RELAY_ADDRESS));
        new GatewayCTMDeployerDA(_config());
    }

    function test_SyscoinGatewayRejectsWrongCanonicalRelayRuntime() public {
        vm.etch(SYSCOIN_EDGE_DA_RELAY_ADDRESS, hex"60006000f3");
        bytes32 actualHash = SYSCOIN_EDGE_DA_RELAY_ADDRESS.codehash;
        vm.expectRevert(
            abi.encodeWithSelector(
                SyscoinEdgeDARelayCodeHashMismatch.selector,
                SYSCOIN_EDGE_DA_RELAY_ADDRESS,
                SYSCOIN_EDGE_DA_RELAY_RUNTIME_HASH,
                actualHash
            )
        );
        new GatewayCTMDeployerDA(_config());
    }
}
