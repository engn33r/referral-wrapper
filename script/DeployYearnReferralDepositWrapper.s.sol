// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {Script} from "forge-std/Script.sol";
import {YearnReferralDepositWrapper} from "../src/YearnReferralDepositWrapper.sol";

interface ICreateX {
    function deployCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address);
}

/// @notice Foundry deployment script for YearnReferralDepositWrapper.
contract DeployYearnReferralDepositWrapper is Script {
    // CreateX canonical deployment address (see createx.rocks)
    address internal constant CREATE_X = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    function run() external returns (YearnReferralDepositWrapper deployed) {
        bytes32 salt = vm.envOr(
            "DEPLOY_SALT",
            bytes32(uint256(uint160(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e)))
        );
        bytes memory initCode = type(YearnReferralDepositWrapper).creationCode;

        vm.startBroadcast();
        address deployedAddr = ICreateX(CREATE_X).deployCreate2(salt, initCode);
        vm.stopBroadcast();

        require(deployedAddr != address(0), "deployment failed");
        deployed = YearnReferralDepositWrapper(deployedAddr);
    }
}
