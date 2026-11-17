// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AdminTest} from "./_Admin_Shared.t.sol";

import {ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT} from "contracts/common/Config.sol";
import {
    Unauthorized,
    ZKsyncOSChainConfigUpdateWithUnverifiedBatches,
    ZKsyncOSMaxTxGasLimitTooHigh,
    ZKsyncOSMaxTxGasLimitTooLow
} from "contracts/common/L1ContractErrors.sol";
import {NotSettlementLayer, NotZKsyncOS} from "contracts/state-transition/L1StateTransitionErrors.sol";

contract SetZKsyncOSChainConfigTest is AdminTest {
    event NewZKsyncOSMaxTxGasLimit(uint64 oldMaxTxGasLimit, uint64 newMaxTxGasLimit);

    function setUp() public override {
        super.setUp();
        utilsFacet.util_setZksyncOS(true);
    }

    /*//////////////////////////////////////////////////////////////
                        setZKsyncOSMaxTxGasLimit
    //////////////////////////////////////////////////////////////*/

    function test_setZKsyncOSMaxTxGasLimit_revertWhen_calledByNonAdmin() public {
        address nonAdmin = makeAddr("nonAdmin");

        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, nonAdmin));
        adminFacet.setZKsyncOSMaxTxGasLimit(ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);
    }

    // SYSCOIN: Consensus fixes the zkOS transaction-gas limit to one canonical value across server and contracts.
    function testFuzz_setZKsyncOSMaxTxGasLimit_revertWhen_notCanonicalDefault(uint64 newMaxTxGasLimit) public {
        vm.assume(newMaxTxGasLimit != ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);
        vm.startPrank(utilsFacet.util_getAdmin());
        if (newMaxTxGasLimit < ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT) {
            vm.expectRevert(ZKsyncOSMaxTxGasLimitTooLow.selector);
        } else {
            vm.expectRevert(ZKsyncOSMaxTxGasLimitTooHigh.selector);
        }
        adminFacet.setZKsyncOSMaxTxGasLimit(newMaxTxGasLimit);
    }

    function test_setZKsyncOSMaxTxGasLimit_revertWhen_raisedAboveCanonicalDefault() public {
        vm.startPrank(utilsFacet.util_getAdmin());
        vm.expectRevert(ZKsyncOSMaxTxGasLimitTooHigh.selector);
        adminFacet.setZKsyncOSMaxTxGasLimit(ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT * 2);
    }

    function test_setZKsyncOSMaxTxGasLimit_revertWhen_notZKsyncOS() public {
        utilsFacet.util_setZksyncOS(false);

        vm.startPrank(utilsFacet.util_getAdmin());
        vm.expectRevert(NotZKsyncOS.selector);
        adminFacet.setZKsyncOSMaxTxGasLimit(ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);
    }

    function test_setZKsyncOSMaxTxGasLimit_revertWhen_notSettlementLayer() public {
        utilsFacet.util_setSettlementLayer(makeAddr("settlementLayer"));

        vm.startPrank(utilsFacet.util_getAdmin());
        vm.expectRevert(NotSettlementLayer.selector);
        adminFacet.setZKsyncOSMaxTxGasLimit(ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);
    }

    function test_setZKsyncOSMaxTxGasLimit_revertWhen_unverifiedBatchesExist() public {
        utilsFacet.util_setTotalBatchesCommitted(2);
        utilsFacet.util_setTotalBatchesVerified(1);

        vm.startPrank(utilsFacet.util_getAdmin());
        vm.expectRevert(abi.encodeWithSelector(ZKsyncOSChainConfigUpdateWithUnverifiedBatches.selector, 1, 2));
        adminFacet.setZKsyncOSMaxTxGasLimit(ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);
    }

    function test_setZKsyncOSMaxTxGasLimit_acceptsCanonicalDefaultIdempotently() public {
        vm.startPrank(utilsFacet.util_getAdmin());
        // The effective old value is already the default when the storage slot is unset.
        vm.expectEmit(true, true, true, true, address(adminFacet));
        emit NewZKsyncOSMaxTxGasLimit(ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT, ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);
        adminFacet.setZKsyncOSMaxTxGasLimit(ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);
        assertEq(utilsFacet.util_getZKsyncOSMaxTxGasLimit(), ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);

        // A second call is a true no-op in value terms and preserves the same event semantics.
        vm.expectEmit(true, true, true, true, address(adminFacet));
        emit NewZKsyncOSMaxTxGasLimit(ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT, ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);
        adminFacet.setZKsyncOSMaxTxGasLimit(ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);
        assertEq(utilsFacet.util_getZKsyncOSMaxTxGasLimit(), ZKSYNC_OS_DEFAULT_MAX_TX_GAS_LIMIT);
    }
}
