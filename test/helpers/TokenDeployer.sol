// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Offsets} from "../../src/Offsets.sol";

/// @dev Test-only factory for checking the immediate deployer's allocation and launch transfers.
contract TokenDeployer {
    function deploy() external returns (Offsets) {
        return new Offsets();
    }

    function deployDeterministic(bytes32 salt) external returns (Offsets) {
        return new Offsets{salt: salt}();
    }

    function move(Offsets token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}
