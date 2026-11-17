// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {L1DAValidatorOutput} from "../../contracts/IL1DAValidator.sol";
import {
    BitcoinDAPrecompileCallFailed,
    BitcoinDAVerificationFailed,
    InvalidBlobsDAInputLength,
    InvalidBlobsPublished
} from "../../contracts/DAContractsErrors.sol";
import {SyscoinL1DAValidatorZKsyncOS} from "../../contracts/SyscoinL1DAValidatorZKsyncOS.sol";
import {
    SYSCOIN_BITCOIN_DA_PRECOMPILE_ADDRESS,
    SYSCOIN_DA_MAX_BLOBS_PER_BATCH
} from "../../contracts/SyscoinDAUtils.sol";

/// @dev SYSCOIN: Exercises the fixed Bitcoin-DA precompile protocol used by the direct zkOS validator.
contract SyscoinL1DAValidatorZKsyncOSTest is Test {
    SyscoinL1DAValidatorZKsyncOS internal validator;

    function setUp() public {
        validator = new SyscoinL1DAValidatorZKsyncOS();
    }

    function testCheckDAAcceptsOrderedAvailableReferences() public {
        bytes32 firstHash = keccak256("first-bitcoin-da-blob");
        bytes32 secondHash = keccak256("second-bitcoin-da-blob");
        bytes memory operatorInput = abi.encodePacked(firstHash, secondHash);

        _mockAvailable(firstHash);
        _mockAvailable(secondHash);
        vm.expectCall(SYSCOIN_BITCOIN_DA_PRECOMPILE_ADDRESS, abi.encodePacked(firstHash));
        vm.expectCall(SYSCOIN_BITCOIN_DA_PRECOMPILE_ADDRESS, abi.encodePacked(secondHash));

        // solhint-disable-next-line func-named-parameters
        L1DAValidatorOutput memory output = validator.checkDA(1, 7, keccak256(operatorInput), operatorInput, 32);

        assertEq(output.stateDiffHash, bytes32(0));
        assertEq(output.blobsLinearHashes.length, 0);
        assertEq(output.blobsOpeningCommitments.length, 0);
    }

    function testCheckDARejectsEmptyInput() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidBlobsDAInputLength.selector, 0));
        // solhint-disable-next-line func-named-parameters
        validator.checkDA(1, 7, keccak256(""), hex"", 32);
    }

    function testCheckDARejectsPartialReference() public {
        bytes memory operatorInput = new bytes(31);
        vm.expectRevert(abi.encodeWithSelector(InvalidBlobsDAInputLength.selector, operatorInput.length));
        // solhint-disable-next-line func-named-parameters
        validator.checkDA(1, 7, keccak256(operatorInput), operatorInput, 32);
    }

    function testCheckDARejectsMoreThanThirtyTwoReferences() public {
        bytes memory operatorInput = new bytes((SYSCOIN_DA_MAX_BLOBS_PER_BATCH + 1) * 32);
        vm.expectRevert(abi.encodeWithSelector(InvalidBlobsDAInputLength.selector, operatorInput.length));
        // solhint-disable-next-line func-named-parameters
        validator.checkDA(1, 7, keccak256(operatorInput), operatorInput, 32);
    }

    function testCheckDARejectsUnavailableReference() public {
        bytes32 dataHash = keccak256("unavailable-bitcoin-da-blob");
        bytes memory operatorInput = abi.encodePacked(dataHash);
        vm.mockCall(SYSCOIN_BITCOIN_DA_PRECOMPILE_ADDRESS, operatorInput, hex"");

        vm.expectRevert(BitcoinDAVerificationFailed.selector);
        // solhint-disable-next-line func-named-parameters
        validator.checkDA(1, 7, keccak256(operatorInput), operatorInput, 32);
    }

    function testCheckDARejectsWrongPrecompileResult() public {
        bytes32 dataHash = keccak256("available-bitcoin-da-blob");
        bytes memory operatorInput = abi.encodePacked(dataHash);
        vm.mockCall(
            SYSCOIN_BITCOIN_DA_PRECOMPILE_ADDRESS,
            operatorInput,
            abi.encodePacked(keccak256("different-bitcoin-da-blob"))
        );

        vm.expectRevert(BitcoinDAVerificationFailed.selector);
        // solhint-disable-next-line func-named-parameters
        validator.checkDA(1, 7, keccak256(operatorInput), operatorInput, 32);
    }

    function testCheckDARejectsRevertingPrecompile() public {
        bytes32 dataHash = keccak256("available-bitcoin-da-blob");
        bytes memory operatorInput = abi.encodePacked(dataHash);
        vm.mockCallRevert(SYSCOIN_BITCOIN_DA_PRECOMPILE_ADDRESS, operatorInput, hex"");

        vm.expectRevert(BitcoinDAPrecompileCallFailed.selector);
        // solhint-disable-next-line func-named-parameters
        validator.checkDA(1, 7, keccak256(operatorInput), operatorInput, 32);
    }

    function testCheckDARejectsCommitmentMismatch() public {
        bytes32 dataHash = keccak256("available-bitcoin-da-blob");
        bytes memory operatorInput = abi.encodePacked(dataHash);
        bytes32 wrongCommitment = keccak256("wrong-commitment");
        _mockAvailable(dataHash);

        vm.expectRevert(
            abi.encodeWithSelector(InvalidBlobsPublished.selector, keccak256(operatorInput), wrongCommitment)
        );
        // solhint-disable-next-line func-named-parameters
        validator.checkDA(1, 7, wrongCommitment, operatorInput, 32);
    }

    function _mockAvailable(bytes32 _dataHash) internal {
        vm.mockCall(SYSCOIN_BITCOIN_DA_PRECOMPILE_ADDRESS, abi.encodePacked(_dataHash), abi.encodePacked(_dataHash));
    }
}
