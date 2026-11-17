// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

/// @dev SYSCOIN: Isolate admission limits from Config.sol to retain the frozen DA relay identity.
/// The untouched vendor gas constants in Config.sol are not used by admission or upgrade paths.
uint256 constant PRIORITY_TX_MAX_GAS_LIMIT = 1 << 24;

/// @dev Genesis and protocol upgrades keep their separate execution allowance.
uint256 constant UPGRADE_TX_MAX_GAS_LIMIT = 72_000_000;

/// @dev Fresh chains start with the same bounded priority-admission ceiling.
uint64 constant DEFAULT_PRIORITY_TX_MAX_GAS_LIMIT = uint64(PRIORITY_TX_MAX_GAS_LIMIT);
