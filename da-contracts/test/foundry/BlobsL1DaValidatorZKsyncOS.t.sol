// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {BlobsL1DAValidatorZKsyncOS} from "../../contracts/BlobsL1DAValidatorZKsyncOS.sol";
import {
    BitcoinDAPrecompileCallFailed,
    BitcoinDAVerificationFailed,
    InvalidBlobsPublished,
    InvalidBlobsDAInputLength
} from "../../contracts/DAContractsErrors.sol";
import {L1DAValidatorOutput} from "../../contracts/IL1DAValidator.sol";

/// @dev Etched at `0x63` so `staticcall` succeeds with non-empty return data.
contract BitcoinDAMockOk {
    fallback() external {
        assembly {
            mstore(0, 1)
            return(0, 32)
        }
    }
}

/// @dev Etched at `0x63` to simulate DA lookup failure.
contract BitcoinDAMockFail {
    fallback() external {
        revert();
    }
}

/// @dev Etched at `0x63`: call succeeds but returns no data.
contract BitcoinDAMockEmptyReturn {
    fallback() external {
        assembly {
            return(0, 0)
        }
    }
}

contract BlobsL1DAValidatorZKsyncOSTest is Test {
    BlobsL1DAValidatorZKsyncOS internal validator;

    function setUp() public {
        validator = new BlobsL1DAValidatorZKsyncOS();
        vm.etch(address(uint160(0x63)), address(new BitcoinDAMockOk()).code);
    }

    function testCheckDAInvalidLength() public {
        bytes memory badInput = hex"1234";
        vm.expectRevert(abi.encodeWithSelector(InvalidBlobsDAInputLength.selector, 2));
        validator.checkDA(1, 1, bytes32(0), badInput, 0);
    }

    function testCheckDAEmptyInput() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidBlobsDAInputLength.selector, 0));
        validator.checkDA(1, 1, bytes32(0), "", 0);
    }

    function testCheckDAInvalidBlobsPublished() public {
        bytes32 h0 = keccak256("a");
        bytes32 h1 = keccak256("b");
        bytes memory operatorInput = abi.encodePacked(h0, h1);
        bytes32 wrong = keccak256("wrong");
        vm.expectRevert(abi.encodeWithSelector(InvalidBlobsPublished.selector, keccak256(operatorInput), wrong));
        validator.checkDA(1, 1, wrong, operatorInput, 0);
    }

    function testCheckDAVerifiesCorrectly() public {
        bytes32 h0 = keccak256("a");
        bytes32 h1 = keccak256("b");
        bytes memory operatorInput = abi.encodePacked(h0, h1);
        bytes32 expectedHash = keccak256(operatorInput);

        L1DAValidatorOutput memory out = validator.checkDA(1, 1, expectedHash, operatorInput, 0);

        assertEq(out.stateDiffHash, bytes32(0));
        assertEq(out.blobsLinearHashes.length, 0);
    }

    function testCheckDABitcoinDAPrecompileFails() public {
        vm.etch(address(uint160(0x63)), address(new BitcoinDAMockFail()).code);

        bytes32 h0 = keccak256("a");
        bytes memory operatorInput = abi.encodePacked(h0);
        vm.expectRevert(BitcoinDAPrecompileCallFailed.selector);
        validator.checkDA(1, 1, keccak256(operatorInput), operatorInput, 0);
    }

    function testCheckDABitcoinDAEmptyResult() public {
        vm.etch(address(uint160(0x63)), address(new BitcoinDAMockEmptyReturn()).code);

        bytes32 h0 = keccak256("a");
        bytes memory operatorInput = abi.encodePacked(h0);
        vm.expectRevert(BitcoinDAVerificationFailed.selector);
        validator.checkDA(1, 1, keccak256(operatorInput), operatorInput, 0);
    }
}
