// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title babyIMD (bIMD)
/// @notice ERC20. The whole supply is minted once, in the constructor, to the deployer (the launch factory).
///         One rule: bIMD the launch factory sends to DEV is split on arrival, 1/11 kept by DEV (at most
///         DEV_SHARE per transfer) and the rest burned to DEAD. Every other transfer moves exactly the amount.
///         No owner, no mint or burn function, no fee, no pause, no blacklist, no limit.
contract BabyIMD is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;
    /// @notice 5% of the supply: the most DEV keeps from one transfer of the launch factory.
    uint256 public constant DEV_SHARE = 50_000_000e18;
    address public constant DEV = 0x8Ad18E99F4C8d8406f9Ba8899CF308000518A981;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @notice The launch factory: the deployer, holder of the whole supply at launch.
    address public immutable FACTORY;

    constructor() ERC20("babyIMD", "bIMD") {
        FACTORY = msg.sender;
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == FACTORY && to == DEV) {
            uint256 kept = value / 11;
            if (kept > DEV_SHARE) kept = DEV_SHARE;
            super._update(from, DEAD, value - kept);
            super._update(from, DEV, kept);
        } else {
            super._update(from, to, value);
        }
    }
}
