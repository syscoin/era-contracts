// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {FeeParams} from "../../state-transition/chain-deps/ZKChainStorage.sol";
import {MailboxFacet} from "../../state-transition/chain-deps/facets/Mailbox.sol";
import {REQUIRED_L2_GAS_PRICE_PER_PUBDATA} from "../../common/Config.sol";

contract MailboxFacetTest is MailboxFacet {
    // add this to be excluded from coverage report
    function test() internal virtual {}

    constructor(uint256 _eraChainId, uint256 _l1ChainId) MailboxFacet(_eraChainId, _l1ChainId) {
        s.admin = msg.sender;
    }

    function setFeeParams(FeeParams memory _feeParams) external {
        s.feeParams = _feeParams;
    }

    function getL2GasPrice(uint256 _l1GasPrice) external view returns (uint256) {
        return _deriveL2GasPrice(_l1GasPrice, REQUIRED_L2_GAS_PRICE_PER_PUBDATA);
    }
}
