// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {L2DACommitmentScheme} from "./Config.sol";

// SYSCOIN: canonical L1 identity used by production-safety gates.
uint256 constant SYSCOIN_MAINNET_CHAIN_ID = 57;

// Canonical Syscoin DA configuration shared by final-L1 and Gateway settlement.
L2DACommitmentScheme constant SYSCOIN_ROLLUP_L2_DA_COMMITMENT_SCHEME = L2DACommitmentScheme.BLOBS_ZKSYNC_OS;
uint8 constant SYSCOIN_RELAYED_EDGE_DA_VALIDATOR_VERSION = 1;
bytes constant SYSCOIN_EDGE_DA_REFS_DOMAIN = "SYSCOIN_EDGE_DA_REFS_V1";
address constant SYSCOIN_BITCOIN_DA_PRECOMPILE = address(0x63);
uint16 constant SYSCOIN_BITCOIN_DA_PRECOMPILE_GAS = 1400;
uint256 constant SYSCOIN_EDGE_DA_REF_HEAD_BYTES = 32 * 5;
uint256 constant SYSCOIN_DA_REFERENCE_SIZE = 32;
uint256 constant SYSCOIN_DA_MAX_REFS_PER_BATCH = 32;
