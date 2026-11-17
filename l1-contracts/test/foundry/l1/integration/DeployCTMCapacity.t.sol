// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {L1ContractDeployer} from "./_SharedL1ContractDeployer.t.sol";
import {FixedForceDeploymentsData} from "contracts/state-transition/l2-deps/IL2GenesisUpgrade.sol";

contract DeployCTMCapacityTest is L1ContractDeployer {
    function test_freshCTMUsesBridgehubCapacity() public {
        // SYSCOIN: execute the real root and CTM deployment flow. Do not populate the CTM
        // capacity in a test override: that would hide a missing Bridgehub read.
        _deployL1Contracts();

        uint256 rootCapacity = addresses.bridgehub.MAX_NUMBER_OF_ZK_CHAINS();
        assertGt(rootCapacity, 0, "root test configuration must have nonzero capacity");
        assertEq(
            ecosystemConfig.contracts.maxNumberOfChains,
            rootCapacity,
            "fresh CTM config did not inherit root Bridgehub capacity"
        );

        FixedForceDeploymentsData memory forceDeploymentsData = abi.decode(
            ctmScript.getForceDeploymentsData(),
            (FixedForceDeploymentsData)
        );
        assertEq(
            forceDeploymentsData.maxNumberOfZKChains,
            rootCapacity,
            "fresh CTM force-deployment data did not inherit root Bridgehub capacity"
        );
    }
}
