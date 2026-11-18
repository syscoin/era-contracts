// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// SYSCOIN: Key rotation coverage must exercise genuine proofs through both production verifier layers.

import {Test} from "forge-std/Test.sol";
import {IVerifier} from "contracts/state-transition/chain-interfaces/IVerifier.sol";
import {IVerifierV2} from "contracts/state-transition/chain-interfaces/IVerifierV2.sol";
import {NonZeroCarriedHash, ZKsyncOSDualVerifier} from "contracts/state-transition/verifiers/ZKsyncOSDualVerifier.sol";
import {ZKsyncOSVerifierFflonk} from "contracts/state-transition/verifiers/ZKsyncOSVerifierFflonk.sol";
import {ZKsyncOSVerifierPlonk} from "contracts/state-transition/verifiers/ZKsyncOSVerifierPlonk.sol";
import {ZKsyncOSProofFixtures} from "foundry-test/l1/fixtures/ZKsyncOSProofFixtures.sol";

contract ZKsyncOSVerifierProofTest is Test {
    ZKsyncOSVerifierPlonk internal plonk;
    ZKsyncOSDualVerifier internal router;

    function setUp() public {
        plonk = new ZKsyncOSVerifierPlonk();
        router = new ZKsyncOSDualVerifier(
            IVerifierV2(address(new ZKsyncOSVerifierFflonk())),
            IVerifier(address(plonk)),
            address(this)
        );
    }

    function test_activeVerificationKeyAndInputBinding() public view {
        ZKsyncOSProofFixtures.Fixture memory fixture = _activeProof();
        assertEq(plonk.verificationKeyHash(), fixture.verificationKeyHash);
        assertEq(router.verificationKeyHash(), fixture.verificationKeyHash);
        assertFalse(router.IS_TESTNET_VERIFIER());
        assertEq(router.computeZKsyncOSHash(0, fixture.batchHashes), fixture.publicInputs[0]);
    }

    function test_acceptsGenuineProofInPlonkAndProductionRouter() public view {
        _assertAccepted(_activeProof());
    }

    function test_rejectsChangedPublicInput() public {
        ZKsyncOSProofFixtures.Fixture memory fixture = _activeProof();
        fixture.publicInputs[0] ^= 1;
        vm.expectRevert();
        plonk.verify(fixture.publicInputs, fixture.proof);
    }

    function test_rejectsChangedBatchHashInProductionRouter() public {
        ZKsyncOSProofFixtures.Fixture memory fixture = _activeProof();
        fixture.batchHashes[0] ^= 1;
        uint256[] memory routedProof = _routedProof(fixture.proof);
        vm.expectRevert();
        router.verify(fixture.batchHashes, routedProof);
    }

    function test_rejectsChangedOpeningInPlonkAndProductionRouter() public {
        ZKsyncOSProofFixtures.Fixture memory fixture = _activeProof();
        // Mutate a scalar opening, retaining the well-formed curve points and proof length.
        fixture.proof[ZKsyncOSProofFixtures.STATE_POLY_OPENING_INDEX] ^= 1;
        uint256[] memory routedProof = _routedProof(fixture.proof);
        vm.expectRevert();
        plonk.verify(fixture.publicInputs, fixture.proof);
        vm.expectRevert();
        router.verify(fixture.batchHashes, routedProof);
    }

    function test_rejectsCarriedHashWithGenuineProof() public {
        ZKsyncOSProofFixtures.Fixture memory fixture = _activeProof();
        uint256[] memory routedProof = _routedProof(fixture.proof);
        routedProof[1] = 1;
        vm.expectRevert(NonZeroCarriedHash.selector);
        router.verify(fixture.batchHashes, routedProof);
    }

    function test_rejectsDifferentGuestProofInPlonkAndProductionRouter() public {
        ZKsyncOSProofFixtures.Fixture memory fixture = _otherGuestProof();
        ZKsyncOSProofFixtures.Fixture memory active = _activeProof();
        // Both genuine proofs bind the same batch hashes; only their guest verification keys differ.
        assertEq(fixture.publicInputs, active.publicInputs);
        assertEq(fixture.batchHashes, active.batchHashes);
        assertNotEq(fixture.verificationKeyHash, plonk.verificationKeyHash());
        uint256[] memory routedProof = _routedProof(fixture.proof);
        vm.expectRevert();
        plonk.verify(fixture.publicInputs, fixture.proof);
        vm.expectRevert();
        router.verify(fixture.batchHashes, routedProof);
    }

    function _otherGuestProof() internal pure returns (ZKsyncOSProofFixtures.Fixture memory) {
        return ZKsyncOSProofFixtures.correctedSignedTransfer();
    }

    function _activeProof() internal pure returns (ZKsyncOSProofFixtures.Fixture memory) {
        return ZKsyncOSProofFixtures.retainedSignedTransfer();
    }

    function _assertAccepted(ZKsyncOSProofFixtures.Fixture memory _fixture) internal view {
        assertTrue(plonk.verify(_fixture.publicInputs, _fixture.proof));
        assertTrue(router.verify(_fixture.batchHashes, _routedProof(_fixture.proof)));
    }

    function _routedProof(uint256[] memory _proof) internal pure returns (uint256[] memory routedProof) {
        uint256 proofLength = _proof.length;
        routedProof = new uint256[](proofLength + ZKsyncOSProofFixtures.ROUTER_HEADER_WORDS);
        routedProof[0] = ZKsyncOSProofFixtures.PLONK_V8_SELECTOR;
        for (uint256 i; i < proofLength; ++i) {
            routedProof[i + ZKsyncOSProofFixtures.ROUTER_HEADER_WORDS] = _proof[i];
        }
    }
}
