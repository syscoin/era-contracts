// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ITransactionFilterer} from "../../state-transition/chain-interfaces/ITransactionFilterer.sol";

contract TransactionFiltererTrue is ITransactionFilterer {
    // add this to be excluded from coverage report
    function test() internal virtual {}

    function isTransactionAllowed(
        address,
        address,
        uint256,
        uint256,
        bytes memory,
        address
    ) external pure returns (bool) {
        return true;
    }
}
