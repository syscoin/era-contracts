// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {NonZeroCarriedHash, ZKsyncOSDualVerifier} from "contracts/state-transition/verifiers/ZKsyncOSDualVerifier.sol";
import {ZKsyncOSTestnetVerifier} from "contracts/state-transition/verifiers/ZKsyncOSTestnetVerifier.sol";
import {IVerifier} from "contracts/state-transition/chain-interfaces/IVerifier.sol";
import {IVerifierV2} from "contracts/state-transition/chain-interfaces/IVerifierV2.sol";
import {
    AddressHasNoCode,
    EmptyProofLength,
    MockVerifierNotSupported,
    UnknownVerifierType,
    ZeroAddress
} from "contracts/common/L1ContractErrors.sol";
import {UnknownVerifierVersion} from "contracts/state-transition/L1StateTransitionErrors.sol";
import {SYSCOIN_MAINNET_CHAIN_ID} from "contracts/common/SyscoinConfig.sol";
import {MAINNET_CHAIN_ID} from "contracts/common/Config.sol";

// SYSCOIN: This entire downstream test adaptation covers the single V8 verifier selector,
// governance ownership, and explicitly isolated testnet mock path; every divergence is intentional.
/// @notice Mock retained FFLONK verifier for deployment/introspection tests.
contract MockFflonkVerifierOS is IVerifierV2 {
    bytes32 public constant VK_HASH = keccak256("fflonk_os_vk");

    function verify(uint256[] calldata, uint256[] calldata) external pure override returns (bool) {
        return true;
    }

    function verificationKeyHash() external pure override returns (bytes32) {
        return VK_HASH;
    }
}

/// @notice Mock PLONK verifier for testing
contract MockPlonkVerifierOS is IVerifier {
    bytes32 public constant VK_HASH = keccak256("plonk_os_vk");
    bool public shouldVerify = true;

    function verify(uint256[] calldata, uint256[] calldata) external view override returns (bool) {
        return shouldVerify;
    }

    function verificationKeyHash() external pure override returns (bytes32) {
        return VK_HASH;
    }

    function setShouldVerify(bool _value) external {
        shouldVerify = _value;
    }
}

/// @notice Unit tests for ZKsyncOSDualVerifier contract
contract ZKsyncOSDualVerifierTest is Test {
    event VerifierReplaced(uint32 indexed version, address indexed oldVerifier, address indexed newVerifier);

    ZKsyncOSDualVerifier public verifier;
    MockFflonkVerifierOS public fflonkVerifier;
    MockPlonkVerifierOS public plonkVerifier;
    address public owner;

    uint256 internal constant ZKSYNC_OS_PLONK_VERIFICATION_TYPE = 2;
    uint256 internal constant ZKSYNC_OS_MOCK_VERIFICATION_TYPE = 3;
    uint256 internal constant SYSCOIN_TESTNET_L1_CHAIN_ID = 5700;
    uint256 internal constant SYSCOIN_GATEWAY_CHAIN_ID = 57001;

    function setUp() public {
        owner = makeAddr("owner");
        fflonkVerifier = new MockFflonkVerifierOS();
        plonkVerifier = new MockPlonkVerifierOS();
        verifier = new ZKsyncOSDualVerifier(
            IVerifierV2(address(fflonkVerifier)),
            IVerifier(address(plonkVerifier)),
            owner
        );
    }

    // ============ Constructor Tests ============

    function test_constructor_leavesUnusedVersion0Empty() public view {
        assertEq(address(verifier.fflonkVerifiers(0)), address(0));
        assertEq(address(verifier.plonkVerifiers(0)), address(0));
    }

    function test_constructor_setsBothVerifiersAtCanonicalVersion8() public view {
        assertEq(address(verifier.fflonkVerifiers(8)), address(fflonkVerifier));
        assertEq(address(verifier.plonkVerifiers(8)), address(plonkVerifier));
    }

    function test_constructor_revertsForZeroFflonkVerifier() public {
        vm.expectRevert(ZeroAddress.selector);
        new ZKsyncOSDualVerifier(IVerifierV2(address(0)), IVerifier(address(plonkVerifier)), owner);
    }

    function test_constructor_revertsForZeroPlonkVerifier() public {
        vm.expectRevert(ZeroAddress.selector);
        new ZKsyncOSDualVerifier(IVerifierV2(address(fflonkVerifier)), IVerifier(address(0)), owner);
    }

    function test_constructor_revertsForFflonkAddressWithoutCode() public {
        address eoa = makeAddr("fflonkEoa");
        vm.expectRevert(abi.encodeWithSelector(AddressHasNoCode.selector, eoa));
        new ZKsyncOSDualVerifier(IVerifierV2(eoa), IVerifier(address(plonkVerifier)), owner);
    }

    function test_constructor_revertsForPlonkAddressWithoutCode() public {
        address eoa = makeAddr("plonkEoa");
        vm.expectRevert(abi.encodeWithSelector(AddressHasNoCode.selector, eoa));
        new ZKsyncOSDualVerifier(IVerifierV2(address(fflonkVerifier)), IVerifier(eoa), owner);
    }

    function test_constructor_revertsForZeroOwner() public {
        vm.expectRevert(ZeroAddress.selector);
        new ZKsyncOSDualVerifier(IVerifierV2(address(fflonkVerifier)), IVerifier(address(plonkVerifier)), address(0));
    }

    function test_constructor_setsOwner() public view {
        assertEq(verifier.owner(), owner);
    }

    function test_productionAndTestnetModeMarkersAreExplicit() public {
        assertFalse(verifier.IS_TESTNET_VERIFIER());

        ZKsyncOSTestnetVerifier testnetVerifier = new ZKsyncOSTestnetVerifier(
            IVerifierV2(address(fflonkVerifier)),
            IVerifier(address(plonkVerifier)),
            owner,
            SYSCOIN_TESTNET_L1_CHAIN_ID
        );
        assertTrue(testnetVerifier.IS_TESTNET_VERIFIER());
    }

    function test_testnetVerifierConstructor_revertsOnSyscoinMainnetExecutionChain() public {
        vm.chainId(SYSCOIN_MAINNET_CHAIN_ID);
        vm.expectRevert();
        new ZKsyncOSTestnetVerifier(
            IVerifierV2(address(fflonkVerifier)),
            IVerifier(address(plonkVerifier)),
            owner,
            SYSCOIN_TESTNET_L1_CHAIN_ID
        );
    }

    function test_testnetVerifierConstructor_revertsOnEthereumMainnetExecutionChain() public {
        vm.chainId(MAINNET_CHAIN_ID);
        vm.expectRevert();
        new ZKsyncOSTestnetVerifier(
            IVerifierV2(address(fflonkVerifier)),
            IVerifier(address(plonkVerifier)),
            owner,
            SYSCOIN_TESTNET_L1_CHAIN_ID
        );
    }

    // SYSCOIN: Gateway execution must not conceal a production ultimate L1 from the mock-verifier guard.
    function test_testnetVerifierConstructor_revertsForSyscoinMainnetRootOnGateway() public {
        vm.chainId(SYSCOIN_GATEWAY_CHAIN_ID);
        vm.expectRevert();
        new ZKsyncOSTestnetVerifier(
            IVerifierV2(address(fflonkVerifier)),
            IVerifier(address(plonkVerifier)),
            owner,
            SYSCOIN_MAINNET_CHAIN_ID
        );
    }

    function test_testnetVerifierConstructor_revertsForEthereumMainnetRootOnGateway() public {
        vm.chainId(SYSCOIN_GATEWAY_CHAIN_ID);
        vm.expectRevert();
        new ZKsyncOSTestnetVerifier(
            IVerifierV2(address(fflonkVerifier)),
            IVerifier(address(plonkVerifier)),
            owner,
            MAINNET_CHAIN_ID
        );
    }

    function test_testnetVerifierConstructor_revertsForZeroRootChain() public {
        vm.chainId(SYSCOIN_GATEWAY_CHAIN_ID);
        vm.expectRevert();
        new ZKsyncOSTestnetVerifier(IVerifierV2(address(fflonkVerifier)), IVerifier(address(plonkVerifier)), owner, 0);
    }

    function test_testnetVerifierConstructor_succeedsOnTestnetGateway() public {
        vm.chainId(SYSCOIN_GATEWAY_CHAIN_ID);
        ZKsyncOSTestnetVerifier testnetVerifier = new ZKsyncOSTestnetVerifier(
            IVerifierV2(address(fflonkVerifier)),
            IVerifier(address(plonkVerifier)),
            owner,
            SYSCOIN_TESTNET_L1_CHAIN_ID
        );
        assertTrue(testnetVerifier.IS_TESTNET_VERIFIER());
    }

    // ============ atomic PLONK rotation tests ============

    function test_replaceVerifier_ownerCanAtomicallyRotateCanonicalPlonk() public {
        MockPlonkVerifierOS newPlonk = new MockPlonkVerifierOS();

        vm.prank(owner);
        verifier.replaceVerifier(8, IVerifier(address(newPlonk)));

        assertEq(address(verifier.fflonkVerifiers(8)), address(fflonkVerifier));
        assertEq(address(verifier.plonkVerifiers(8)), address(newPlonk));
    }

    function test_replaceVerifier_emitsRotationEvent() public {
        MockPlonkVerifierOS newPlonk = new MockPlonkVerifierOS();

        vm.expectEmit(true, true, true, true, address(verifier));
        emit VerifierReplaced(8, address(plonkVerifier), address(newPlonk));
        vm.prank(owner);
        verifier.replaceVerifier(8, IVerifier(address(newPlonk)));
    }

    function test_replaceVerifier_revertsForNonCanonicalVersionEvenForOwner() public {
        MockPlonkVerifierOS newPlonk = new MockPlonkVerifierOS();

        vm.prank(owner);
        vm.expectRevert(UnknownVerifierVersion.selector);
        verifier.replaceVerifier(1, IVerifier(address(newPlonk)));
        assertEq(address(verifier.plonkVerifiers(8)), address(plonkVerifier));
    }

    function test_replaceVerifier_revertsIfNotOwner() public {
        MockPlonkVerifierOS newPlonk = new MockPlonkVerifierOS();

        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        verifier.replaceVerifier(8, IVerifier(address(newPlonk)));
    }

    function test_replaceVerifier_revertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ZeroAddress.selector);
        verifier.replaceVerifier(8, IVerifier(address(0)));
        assertEq(address(verifier.plonkVerifiers(8)), address(plonkVerifier));
    }

    function test_replaceVerifier_revertsForAddressWithoutCode() public {
        address eoa = makeAddr("replacementEoa");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AddressHasNoCode.selector, eoa));
        verifier.replaceVerifier(8, IVerifier(eoa));
        assertEq(address(verifier.plonkVerifiers(8)), address(plonkVerifier));
    }

    // ============ verify Tests ============

    function test_verify_routesToPlonkVerifier() public view {
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = 123;
        publicInputs[1] = 456;

        // Proof with PLONK type (2) at the sole canonical version 8 slot.
        uint256[] memory proof = new uint256[](4);
        proof[0] = ZKSYNC_OS_PLONK_VERIFICATION_TYPE | (8 << 8); // type 2, canonical version 8
        proof[1] = 0; // initial hash
        proof[2] = 789;
        proof[3] = 101112;

        bool result = verifier.verify(publicInputs, proof);
        assertTrue(result);
    }

    function test_verify_revertsOnEmptyProof() public {
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = 123;
        publicInputs[1] = 456;

        uint256[] memory emptyProof = new uint256[](0);

        vm.expectRevert(EmptyProofLength.selector);
        verifier.verify(publicInputs, emptyProof);
    }

    function test_verify_revertsOnUnknownVerifierType() public {
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = 123;
        publicInputs[1] = 456;

        // Proof with unknown type (0) as first element
        uint256[] memory proof = new uint256[](4);
        proof[0] = 8 << 8; // Unknown type at the configured V8 slot
        proof[1] = 0;
        proof[2] = 789;
        proof[3] = 101112;

        vm.expectRevert(UnknownVerifierType.selector);
        verifier.verify(publicInputs, proof);
    }

    function test_verify_dormantFflonkTypeIsNotRoutable() public {
        uint256[] memory publicInputs = new uint256[](1);
        publicInputs[0] = 123;

        uint256[] memory proof = new uint256[](4);
        proof[0] = uint256(1) | (uint256(8) << 8);
        proof[1] = 0;
        proof[2] = 789;
        proof[3] = 101112;

        vm.expectRevert(UnknownVerifierType.selector);
        verifier.verify(publicInputs, proof);
    }

    function test_verify_revertsOnUnknownVerifierVersion() public {
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = 123;
        publicInputs[1] = 456;

        // Proof with type 2 but version 99 (unknown)
        uint256[] memory proof = new uint256[](4);
        proof[0] = ZKSYNC_OS_PLONK_VERIFICATION_TYPE | (99 << 8); // type 2, version 99
        proof[1] = 0;
        proof[2] = 789;
        proof[3] = 101112;

        vm.expectRevert(UnknownVerifierVersion.selector);
        verifier.verify(publicInputs, proof);
    }

    function test_verify_mockVerifierRevertsInProductionWrapper() public {
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = 123;
        publicInputs[1] = 456;

        // SYSCOIN: production rejects type 3; the explicit testnet subclass overrides this hook.
        uint256[] memory proof = new uint256[](4);
        proof[0] = ZKSYNC_OS_MOCK_VERIFICATION_TYPE | (8 << 8);
        proof[1] = 0;
        proof[2] = 789;
        proof[3] = 101112;

        vm.expectRevert(MockVerifierNotSupported.selector);
        verifier.verify(publicInputs, proof);
    }

    function test_testnetVerifierAcceptsCanonicalFakeProof() public {
        ZKsyncOSTestnetVerifier testnetVerifier = new ZKsyncOSTestnetVerifier(
            IVerifierV2(address(fflonkVerifier)),
            IVerifier(address(plonkVerifier)),
            owner,
            SYSCOIN_TESTNET_L1_CHAIN_ID
        );
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = 123;
        publicInputs[1] = 456;

        uint256[] memory proof = new uint256[](4);
        proof[0] = ZKSYNC_OS_MOCK_VERIFICATION_TYPE | (8 << 8);
        proof[1] = 0;
        proof[2] = 13;
        proof[3] = testnetVerifier.computeZKsyncOSHash(0, publicInputs);

        assertTrue(testnetVerifier.verify(publicInputs, proof));
    }

    function test_verify_plonkReturnsFalse() public {
        plonkVerifier.setShouldVerify(false);

        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = 123;
        publicInputs[1] = 456;

        uint256[] memory proof = new uint256[](4);
        proof[0] = ZKSYNC_OS_PLONK_VERIFICATION_TYPE | (8 << 8);
        proof[1] = 0;
        proof[2] = 789;
        proof[3] = 101112;

        bool result = verifier.verify(publicInputs, proof);
        assertFalse(result);
    }

    // ============ verificationKeyHash Tests ============

    function test_verificationKeyHash_returnsPlonkHash() public view {
        bytes32 vkHash = verifier.verificationKeyHash();
        assertEq(vkHash, plonkVerifier.VK_HASH());
    }

    function test_verificationKeyHash_withTypePlonk() public view {
        bytes32 vkHash = verifier.verificationKeyHash(ZKSYNC_OS_PLONK_VERIFICATION_TYPE | (8 << 8));
        assertEq(vkHash, plonkVerifier.VK_HASH());
    }

    function test_verificationKeyHash_revertsOnUnknownType() public {
        vm.expectRevert(UnknownVerifierType.selector);
        verifier.verificationKeyHash(8 << 8); // Unknown type at the configured V8 slot
    }

    function test_verificationKeyHash_dormantFflonkTypeIsNotRoutable() public {
        vm.expectRevert(UnknownVerifierType.selector);
        verifier.verificationKeyHash(uint256(1) | (uint256(8) << 8));
    }

    function test_verificationKeyHash_revertsOnUnknownVersion() public {
        vm.expectRevert(UnknownVerifierVersion.selector);
        verifier.verificationKeyHash(ZKSYNC_OS_PLONK_VERIFICATION_TYPE | (99 << 8)); // type 2, version 99
    }

    // ============ computeZKsyncOSHash Tests ============

    function testFuzz_verify_revertsOnNonZeroCarriedHash(uint256 carriedHash) public {
        vm.assume(carriedHash != 0);
        uint256[] memory publicInputs = new uint256[](2);
        uint256[] memory proof = new uint256[](3);
        proof[0] = ZKSYNC_OS_PLONK_VERIFICATION_TYPE | (8 << 8);
        proof[1] = carriedHash;

        vm.expectRevert(NonZeroCarriedHash.selector);
        verifier.verify(publicInputs, proof);
    }

    function test_computeZKsyncOSHash_withZeroInitialHash() public view {
        uint256 initialHash = 0;
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = 100;
        publicInputs[1] = 200;

        uint256 result = verifier.computeZKsyncOSHash(initialHash, publicInputs);

        uint256 expected = uint256(keccak256(abi.encodePacked(publicInputs))) >> 32;

        assertEq(result, expected);
    }

    function testFuzz_computeZKsyncOSHash_singleInputWithZeroInitial(uint256 batchHash) public view {
        uint256[] memory publicInputs = new uint256[](1);
        publicInputs[0] = batchHash;

        assertEq(verifier.computeZKsyncOSHash(0, publicInputs), batchHash >> 32);
    }

    function testFuzz_computeZKsyncOSHash_singleInputRejectsNonzeroCarry(uint256 carriedHash, uint256 batchHash) public {
        vm.assume(carriedHash != 0);
        uint256[] memory publicInputs = new uint256[](1);
        publicInputs[0] = batchHash;

        vm.expectRevert(NonZeroCarriedHash.selector);
        verifier.computeZKsyncOSHash(carriedHash, publicInputs);
    }

    // ============ Fuzz Tests ============

    function testFuzz_computeZKsyncOSHash_hashesThreeInputsOnce(uint256 a, uint256 b, uint256 c) public view {
        uint256[] memory publicInputs = new uint256[](3);
        publicInputs[0] = a;
        publicInputs[1] = b;
        publicInputs[2] = c;

        assertEq(verifier.computeZKsyncOSHash(0, publicInputs), uint256(keccak256(abi.encodePacked(a, b, c))) >> 32);
    }

    function testFuzz_verify_revertsOnUnknownType(uint8 verifierType) public {
        vm.assume(verifierType != 2 && verifierType != 3);

        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = 123;
        publicInputs[1] = 456;

        uint256[] memory proof = new uint256[](4);
        proof[0] = verifierType | (8 << 8); // type in lower 8 bits, canonical version 8
        proof[1] = 0;
        proof[2] = 789;
        proof[3] = 101112;

        vm.expectRevert(UnknownVerifierType.selector);
        verifier.verify(publicInputs, proof);
    }
}
