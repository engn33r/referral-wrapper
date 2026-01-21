// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Minimal interface for Yearn V3 vault deposits.
interface IVault {
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function asset() external view returns (address);
}

interface IRegistry {
    function isEndorsed(address vault) external returns (bool);
    function governance() external view returns (address);
}

/// @title Yearn Referral Deposit Wrapper
/// @notice Minimal wrapper to record a referrer on deposits into Yearn V3 vaults.
/// @dev Users receive vault shares directly and can withdraw from the vault without this wrapper.
contract YearnReferralDepositWrapper {
    using SafeERC20 for IERC20;
    /// @notice Emitted after a referral deposit is forwarded to a vault.
    event ReferralDeposit(
        address indexed sender,
        address indexed receiver,
        address indexed referrer,
        address vault,
        uint256 assets,
        uint256 shares
    );
    /// @notice Emitted after a referral mint is forwarded to a vault.
    event ReferralMint(
        address indexed sender,
        address indexed receiver,
        address indexed referrer,
        address vault,
        uint256 assets,
        uint256 shares
    );

    address constant registry = 0xd40ecF29e001c76Dcc4cC0D9cd50520CE845B038;

    /// @notice Deposit assets into a vault and emit a referral event.
    /// @param vault The Yearn V3 vault to deposit into.
    /// @param assets The amount of assets to deposit (use max uint256 to deposit full balance).
    /// @param receiver The address to receive vault shares.
    /// @param referrer The address that referred the depositor.
    /// @return shares The amount of shares minted by the vault.
    function depositWithReferral(
        address vault,
        uint256 assets,
        address receiver,
        address referrer
    ) external returns (uint256 shares) {
        // Official Yearn vaults are endorsed in the registry, prevent deposits to other vaults
        require(IRegistry(registry).isEndorsed(vault), "vault is not endorsed");

        IERC20 token = IERC20(IVault(vault).asset());
        // While this logic duplicates what the Yearn v3 vault does,
        // it is necessary to enable compatibility for the type(uint256).max case
        if (assets == type(uint256).max) {
            assets = token.balanceOf(msg.sender);
        }
        require(assets > 0, "zero assets");

        token.safeTransferFrom(msg.sender, address(this), assets);
        token.forceApprove(vault, assets);

        shares = IVault(vault).deposit(assets, receiver);
        emit ReferralDeposit(msg.sender, receiver, referrer, vault, assets, shares);
    }

    /// @notice Mint shares from a vault and emit a referral event.
    /// @param vault The Yearn V3 vault to mint from.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address to receive vault shares.
    /// @param referrer The address that referred the minter.
    /// @return assets The amount of assets spent to mint the shares.
    function mintWithReferral(
        address vault,
        uint256 shares,
        address receiver,
        address referrer
    ) external returns (uint256 assets) {
        // Official Yearn vaults are endorsed in the registry, prevent deposits to other vaults
        require(IRegistry(registry).isEndorsed(vault), "vault is not endorsed");
        require(shares > 0, "zero shares");

        IERC20 token = IERC20(IVault(vault).asset());
        assets = IVault(vault).previewMint(shares);
        require(assets > 0, "zero assets");

        token.safeTransferFrom(msg.sender, address(this), assets);
        token.forceApprove(vault, assets);

        assets = IVault(vault).mint(shares, receiver);
        emit ReferralMint(msg.sender, receiver, referrer, vault, assets, shares);
    }

    /// @notice Sweep ERC20 tokens held by this wrapper
    /// @param _token The ERC20 token to sweep
    function sweep(
        IERC20 _token
    ) external {
        address gov = IRegistry(registry).governance();
        require(msg.sender == gov, "Must be called by owner");
        _token.safeTransfer(gov, _token.balanceOf(address(this)));
    }
}
