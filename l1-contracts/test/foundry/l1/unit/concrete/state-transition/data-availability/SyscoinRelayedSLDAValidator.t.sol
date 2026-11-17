// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SyscoinRelayedSLDAValidator} from "contracts/state-transition/data-availability/SyscoinRelayedSLDAValidator.sol";
import {L1DAValidatorOutput} from "contracts/state-transition/chain-interfaces/IL1DAValidator.sol";
import {
    L2_BRIDGEHUB_ADDR,
    L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR
} from "contracts/common/l2-helpers/L2ContractAddresses.sol";
import {IL2ToL1MessengerEra} from "contracts/common/l2-helpers/IL2ToL1MessengerEra.sol";
import {IBridgehubBase} from "contracts/core/bridgehub/IBridgehubBase.sol";
import {
    L1DAValidatorInvalidSender,
    SyscoinEdgeDACommitmentMismatch,
    SyscoinEdgeDARefInputMalformed
} from "contracts/state-transition/L1StateTransitionErrors.sol";

/// @dev SYSCOIN: Covers authenticated relay of compact edge-chain DA references into Gateway settlement.
contract SyscoinRelayedSLDAValidatorTest is Test {
    uint256 internal constant CHAIN_ID = 193;
    uint256 internal constant BATCH_NUMBER = 41;
    address internal constant CHAIN_ADDRESS = address(0x1234);

    SyscoinRelayedSLDAValidator internal validator;

    function setUp() public {
        validator = new SyscoinRelayedSLDAValidator();
        vm.etch(L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR, hex"00");
        vm.mockCall(
            L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR,
            abi.encodeWithSelector(IL2ToL1MessengerEra.sendToL1.selector),
            abi.encode(bytes32(0))
        );
        vm.mockCall(
            L2_BRIDGEHUB_ADDR,
            abi.encodeWithSelector(IBridgehubBase.getZKChain.selector, CHAIN_ID),
            abi.encode(CHAIN_ADDRESS)
        );
    }

    function test_RevertWhenSenderIsNotTheChain() public {
        vm.expectRevert(abi.encodeWithSelector(L1DAValidatorInvalidSender.selector, address(this)));
        validator.checkDA(CHAIN_ID, BATCH_NUMBER, bytes32(0), abi.encodePacked(bytes32(uint256(1))), 32);
    }

    function test_RevertWhenCompactInputIsEmpty() public {
        vm.prank(CHAIN_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(SyscoinEdgeDARefInputMalformed.selector, 0));
        validator.checkDA(CHAIN_ID, BATCH_NUMBER, keccak256(""), "", 32);
    }

    function test_RevertWhenCompactInputIsPartialWord() public {
        vm.prank(CHAIN_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(SyscoinEdgeDARefInputMalformed.selector, 0));
        validator.checkDA(CHAIN_ID, BATCH_NUMBER, keccak256(hex"1234"), hex"1234", 32);
    }

    function test_RevertWhenCompactInputHasMoreThan32Refs() public {
        bytes memory refs = new bytes(33 * 32);
        vm.prank(CHAIN_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(SyscoinEdgeDARefInputMalformed.selector, 0));
        validator.checkDA(CHAIN_ID, BATCH_NUMBER, keccak256(refs), refs, 33);
    }

    function test_RevertWhenCommitmentDoesNotMatch() public {
        bytes memory refs = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)));
        bytes32 actual = keccak256(refs);
        bytes32 expected = keccak256("wrong");

        vm.prank(CHAIN_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(SyscoinEdgeDACommitmentMismatch.selector, expected, actual));
        validator.checkDA(CHAIN_ID, BATCH_NUMBER, expected, refs, 32);
    }

    function test_CheckDARelaysCanonicalCompactMessageAndReturnsZeroLengthArrays() public {
        bytes memory refs = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)));
        bytes32 commitment = keccak256(refs);
        bytes memory expectedMessage = abi.encode(uint8(1), CHAIN_ID, BATCH_NUMBER, commitment, refs);

        vm.expectCall(
            L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR,
            abi.encodeWithSelector(IL2ToL1MessengerEra.sendToL1.selector, expectedMessage)
        );
        vm.prank(CHAIN_ADDRESS);
        L1DAValidatorOutput memory output = validator.checkDA(CHAIN_ID, BATCH_NUMBER, commitment, refs, 32);

        assertEq(output.stateDiffHash, bytes32(0));
        assertEq(output.blobsLinearHashes.length, 0);
        assertEq(output.blobsOpeningCommitments.length, 0);
    }
}
