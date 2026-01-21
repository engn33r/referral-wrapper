// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {Test} from "forge-std/Test.sol";
import {YearnReferralDepositWrapper} from "../src/YearnReferralDepositWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault {
    function asset() external view returns (address);
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
}

interface IRegistry {
    function governance() external view returns (address);
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

contract YearnReferralDepositWrapperForkTest is Test {
    address internal constant MAINNET_VAULT = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;
    address internal constant BASE_VAULT = 0xb13CF163d916917d9cD6E836905cA5f12a1dEF4B;
    address internal constant REGISTRY = 0xd40ecF29e001c76Dcc4cC0D9cd50520CE845B038;

    address internal constant USER = address(0xBEEF);
    address internal constant RECEIVER = address(0xCAFE);
    address internal constant REFERRER = address(0xF00D);

    uint256 internal constant DEPOSIT_AMOUNT = 1e6;

    function testForkMainnetDeposit() external {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            emit log_string("MAINNET_RPC_URL not set; skipping fork test");
            return;
        }
        vm.createSelectFork(rpcUrl);
        _runDeposit(MAINNET_VAULT);
    }

    function testForkBaseDeposit() external {
        string memory rpcUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            emit log_string("BASE_RPC_URL not set; skipping fork test");
            return;
        }
        vm.createSelectFork(rpcUrl);
        _runDeposit(BASE_VAULT);
    }

    function testForkMainnetSweep() external {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            emit log_string("MAINNET_RPC_URL not set; skipping fork test");
            return;
        }
        vm.createSelectFork(rpcUrl);
        _runSweep(MAINNET_VAULT);
    }

    function testForkBaseSweep() external {
        string memory rpcUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            emit log_string("BASE_RPC_URL not set; skipping fork test");
            return;
        }
        vm.createSelectFork(rpcUrl);
        _runSweep(BASE_VAULT);
    }

    function testForkMainnetMint() external {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            emit log_string("MAINNET_RPC_URL not set; skipping fork test");
            return;
        }
        vm.createSelectFork(rpcUrl);
        _runMint(MAINNET_VAULT);
    }

    function testForkBaseMint() external {
        string memory rpcUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            emit log_string("BASE_RPC_URL not set; skipping fork test");
            return;
        }
        vm.createSelectFork(rpcUrl);
        _runMint(BASE_VAULT);
    }

    function _runDeposit(address vault) internal {
        YearnReferralDepositWrapper wrapper = new YearnReferralDepositWrapper();
        address asset = IVault(vault).asset();

        deal(asset, USER, DEPOSIT_AMOUNT);

        uint256 receiverSharesBefore = IERC20(vault).balanceOf(RECEIVER);
        uint256 vaultAssetsBefore = IERC20(asset).balanceOf(vault);

        vm.startPrank(USER);
        IERC20(asset).approve(address(wrapper), DEPOSIT_AMOUNT);
        vm.expectEmit(true, true, true, false, address(wrapper));
        emit YearnReferralDepositWrapper.ReferralDeposit(
            USER,
            RECEIVER,
            REFERRER,
            vault,
            DEPOSIT_AMOUNT,
            0
        );
        uint256 shares = wrapper.depositWithReferral(vault, DEPOSIT_AMOUNT, RECEIVER, REFERRER);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(IERC20(asset).balanceOf(address(wrapper)), 0);
        assertEq(IERC20(asset).balanceOf(vault), vaultAssetsBefore + DEPOSIT_AMOUNT);
        assertEq(IERC20(vault).balanceOf(RECEIVER), receiverSharesBefore + shares);
        assertEq(IERC20(vault).balanceOf(address(wrapper)), 0);

    }

    function _runMint(address vault) internal {
        YearnReferralDepositWrapper wrapper = new YearnReferralDepositWrapper();
        address asset = IVault(vault).asset();

        uint256 shares = 10 ** uint256(IERC20Metadata(vault).decimals());
        uint256 assets = IVault(vault).previewMint(shares);
        if (assets == 0) {
            shares = shares * 1_000;
            assets = IVault(vault).previewMint(shares);
        }
        assertGt(assets, 0);

        deal(asset, USER, assets);

        uint256 receiverSharesBefore = IERC20(vault).balanceOf(RECEIVER);
        uint256 vaultAssetsBefore = IERC20(asset).balanceOf(vault);

        vm.startPrank(USER);
        IERC20(asset).approve(address(wrapper), assets);
        vm.expectEmit(true, true, true, false, address(wrapper));
        emit YearnReferralDepositWrapper.ReferralMint(
            USER,
            RECEIVER,
            REFERRER,
            vault,
            assets,
            shares
        );
        uint256 assetsSpent = wrapper.mintWithReferral(vault, shares, RECEIVER, REFERRER);
        vm.stopPrank();

        assertEq(assetsSpent, assets);
        assertEq(IERC20(asset).balanceOf(address(wrapper)), 0);
        assertEq(IERC20(asset).balanceOf(vault), vaultAssetsBefore + assets);
        assertEq(IERC20(vault).balanceOf(RECEIVER), receiverSharesBefore + shares);
        assertEq(IERC20(vault).balanceOf(address(wrapper)), 0);
    }

    function _runSweep(address vault) internal {
        YearnReferralDepositWrapper wrapper = new YearnReferralDepositWrapper();
        address asset = IVault(vault).asset();
        address governance = IRegistry(REGISTRY).governance();

        uint256 amount = 123_456;
        deal(asset, address(wrapper), amount);

        vm.prank(USER);
        vm.expectRevert("Must be called by owner");
        wrapper.sweep(IERC20(asset));

        uint256 governanceBefore = IERC20(asset).balanceOf(governance);
        vm.prank(governance);
        wrapper.sweep(IERC20(asset));

        assertEq(IERC20(asset).balanceOf(address(wrapper)), 0);
        assertEq(IERC20(asset).balanceOf(governance), governanceBefore + amount);
    }
}
