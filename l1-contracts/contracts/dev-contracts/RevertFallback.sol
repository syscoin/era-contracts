// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

contract RevertFallback {
    // add this to be excluded from coverage report
    function test() internal virtual {}

    fallback() external payable {
        revert();
    }
}
