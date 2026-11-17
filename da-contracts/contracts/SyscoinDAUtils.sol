// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

/// @dev SYSCOIN: Raw data-hash availability precompile exposed by Syscoin NEVM.
address constant SYSCOIN_BITCOIN_DA_PRECOMPILE_ADDRESS = address(0x63);

/// @dev SYSCOIN: Fixed gas charged by the raw data-hash availability precompile.
uint16 constant SYSCOIN_BITCOIN_DA_PRECOMPILE_GAS = 1400;

/// @dev SYSCOIN: Size of one compact Bitcoin DA identifier.
uint256 constant SYSCOIN_DA_REFERENCE_SIZE = 32;

/// @dev SYSCOIN: Maximum number of 2 MiB Bitcoin DA blobs accepted for one batch.
uint256 constant SYSCOIN_DA_MAX_BLOBS_PER_BATCH = 32;
