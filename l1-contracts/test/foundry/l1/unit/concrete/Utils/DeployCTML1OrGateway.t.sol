// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployCTML1OrGateway} from "deploy-scripts/ctm/DeployCTML1OrGateway.sol";
import {IVerifier} from "contracts/state-transition/chain-interfaces/IVerifier.sol";
import {IVerifierV2} from "contracts/state-transition/chain-interfaces/IVerifierV2.sol";
import {ZKsyncOSDualVerifier} from "contracts/state-transition/verifiers/ZKsyncOSDualVerifier.sol";
import {SYSCOIN_MAINNET_CHAIN_ID} from "contracts/common/SyscoinConfig.sol";

contract DeployCTML1OrGatewayTest is Test {
    string internal constant ZKSYNC_OS_MOCK_VERIFIER_ENV = "SYSCOIN_ZKSYNC_OS_MOCK_VERIFIER";
    uint256 internal constant SYSCOIN_TESTNET_L1_CHAIN_ID = 5700;

    function checkVerifierOwnership(address _verifier, address _governance) external {
        DeployCTML1OrGateway.transferVerifierOwnership(_verifier, _governance, true);
    }

    function test_zkSyncOSMockVerifierDefaultsToFalse() public pure {
        assertFalse(DeployCTML1OrGateway.resolveTestnetVerifierMode(true, false));
    }

    function test_zkSyncOSMockVerifierRequiresExplicitTrueEnv() public {
        vm.setEnv(ZKSYNC_OS_MOCK_VERIFIER_ENV, "true");

        bool explicitOptIn = vm.envOr(ZKSYNC_OS_MOCK_VERIFIER_ENV, false);
        assertTrue(DeployCTML1OrGateway.resolveTestnetVerifierMode(true, explicitOptIn));

        vm.setEnv(ZKSYNC_OS_MOCK_VERIFIER_ENV, "false");
    }

    function test_genericEraPreservesTestnetVerifierDefault() public pure {
        assertTrue(DeployCTML1OrGateway.resolveTestnetVerifierMode(false, false));
        assertTrue(DeployCTML1OrGateway.resolveTestnetVerifierMode(false, true));
    }

    // SYSCOIN: preserve the pinned-upstream three-word production constructor surface.
    function test_zkSyncOSProductionVerifierCreationArgsRetainFflonk() public {
        address fflonk = makeAddr("fflonk");
        address plonk = makeAddr("plonk");
        address owner = makeAddr("owner");

        bytes memory args = DeployCTML1OrGateway.verifierCreationArgs(
            true,
            false,
            fflonk,
            plonk,
            owner,
            SYSCOIN_MAINNET_CHAIN_ID
        );

        assertEq(args, abi.encode(fflonk, plonk, owner));
    }

    function test_zkSyncOSTestnetVerifierCreationArgsCarryRootL1() public {
        address fflonk = makeAddr("fflonk");
        address plonk = makeAddr("plonk");
        address owner = makeAddr("owner");

        bytes memory args = DeployCTML1OrGateway.verifierCreationArgs(
            true,
            true,
            fflonk,
            plonk,
            owner,
            SYSCOIN_TESTNET_L1_CHAIN_ID
        );

        assertEq(args, abi.encode(fflonk, plonk, owner, SYSCOIN_TESTNET_L1_CHAIN_ID));
    }

    function test_genericEraVerifierCreationArgsRemainUpstreamEncoding() public {
        address fflonk = makeAddr("fflonk");
        address plonk = makeAddr("plonk");
        address owner = makeAddr("ignoredOwner");

        bytes memory args = DeployCTML1OrGateway.verifierCreationArgs(
            false,
            true,
            fflonk,
            plonk,
            owner,
            SYSCOIN_MAINNET_CHAIN_ID
        );

        assertEq(args, abi.encode(fflonk, plonk));
    }

    function test_freshZkSyncOSVerifierStartsWithCompletedGovernanceOwnership() public {
        address governance = makeAddr("governance");
        ZKsyncOSDualVerifier verifier = new ZKsyncOSDualVerifier(
            IVerifierV2(address(this)),
            IVerifier(address(this)),
            governance
        );

        // The shared updateOwners step is a postcondition check. It must be an
        // idempotent no-op even though this caller is not governance.
        DeployCTML1OrGateway.transferVerifierOwnership(address(verifier), governance, true);

        assertEq(verifier.owner(), governance);
        assertEq(verifier.pendingOwner(), address(0));
    }

    function test_verifierOwnershipCheckRejectsWrongOwner() public {
        address governance = makeAddr("governance");
        ZKsyncOSDualVerifier verifier = new ZKsyncOSDualVerifier(
            IVerifierV2(address(this)),
            IVerifier(address(this)),
            address(this)
        );

        vm.expectRevert();
        this.checkVerifierOwnership(address(verifier), governance);
    }

    function test_verifierOwnershipCheckRejectsPendingOnlyGovernance() public {
        address governance = makeAddr("governance");
        ZKsyncOSDualVerifier verifier = new ZKsyncOSDualVerifier(
            IVerifierV2(address(this)),
            IVerifier(address(this)),
            address(this)
        );
        verifier.transferOwnership(governance);

        vm.expectRevert();
        this.checkVerifierOwnership(address(verifier), governance);
    }
}
