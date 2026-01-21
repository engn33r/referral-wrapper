// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {Test} from "forge-std/Test.sol";
import {YearnReferralDepositWrapper} from "../src/YearnReferralDepositWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;

    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "allowance");
        _allowances[from][msg.sender] = currentAllowance - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(_balances[from] >= amount, "balance");
        _balances[from] -= amount;
        _balances[to] += amount;
    }
}

contract MockERC20ForceApprove is MockERC20 {
    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_) {}

    function approve(address spender, uint256 amount) public override returns (bool) {
        require(amount == 0 || _allowances[msg.sender][spender] == 0, "force-approve");
        return super.approve(spender, amount);
    }
}

contract MockVault {
    address public asset;

    address public lastSender;
    address public lastReceiver;
    uint256 public lastAssets;
    uint256 public lastShares;

    constructor(address asset_) {
        asset = asset_;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(assets > 0, "cannot deposit zero");
        IERC20(asset).transferFrom(msg.sender, address(this), assets);
        lastSender = msg.sender;
        lastReceiver = receiver;
        lastAssets = assets;
        lastShares = assets;
        return assets;
    }
}

contract MockRegistry {
    function isEndorsed(address vault) external pure returns (bool) {
        if (vault == address(0)) return false;
        return true;
    }

    function governance() external pure returns (address) {
        return address(0xB0B);
    }
}

contract YearnReferralDepositWrapperTest is Test {
    event ReferralDeposit(
        address indexed sender,
        address indexed receiver,
        address indexed referrer,
        address vault,
        uint256 assets,
        uint256 shares
    );

    YearnReferralDepositWrapper internal wrapper;
    MockERC20 internal token;
    MockVault internal vault;

    address internal constant REGISTRY = 0xd40ecF29e001c76Dcc4cC0D9cd50520CE845B038;
    address internal constant GOVERNANCE = address(0xB0B);
    address internal user = address(0xBEEF);
    address internal receiver = address(0xCAFE);
    address internal referrer = address(0xF00D);

    function setUp() external {
        MockRegistry mockRegistry = new MockRegistry();
        vm.etch(REGISTRY, address(mockRegistry).code);
        wrapper = new YearnReferralDepositWrapper();
        token = new MockERC20("Mock Token", "MOCK");
        vault = new MockVault(address(token));
    }

    function testDepositWithReferralEmitsAndTransfers() external {
        uint256 amount = 1_234e18;
        token.mint(user, amount);

        vm.startPrank(user);
        IERC20(address(token)).approve(address(wrapper), amount);

        vm.expectEmit(true, true, true, true);
        emit ReferralDeposit(user, receiver, referrer, address(vault), amount, amount);

        uint256 shares = wrapper.depositWithReferral(address(vault), amount, receiver, referrer);
        vm.stopPrank();

        assertEq(shares, amount);
        assertEq(IERC20(address(token)).balanceOf(address(vault)), amount);
        assertEq(IERC20(address(token)).balanceOf(address(wrapper)), 0);
        assertEq(vault.lastSender(), address(wrapper));
        assertEq(vault.lastReceiver(), receiver);
        assertEq(vault.lastAssets(), amount);
        assertEq(vault.lastShares(), amount);
    }

    function testDepositWithReferralUsesFullBalanceWhenMax() external {
        uint256 amount = 10e18;
        token.mint(user, amount);

        vm.startPrank(user);
        IERC20(address(token)).approve(address(wrapper), type(uint256).max);
        uint256 shares = wrapper.depositWithReferral(
            address(vault),
            type(uint256).max,
            receiver,
            referrer
        );
        vm.stopPrank();

        assertEq(shares, amount);
        assertEq(IERC20(address(token)).balanceOf(user), 0);
        assertEq(IERC20(address(token)).balanceOf(address(vault)), amount);
    }

    function testDepositWithReferralAllowsZeroReferrer() external {
        uint256 amount = 5e18;
        token.mint(user, amount);

        vm.startPrank(user);
        IERC20(address(token)).approve(address(wrapper), amount);

        vm.expectEmit(true, true, true, true);
        emit ReferralDeposit(user, receiver, address(0), address(vault), amount, amount);

        wrapper.depositWithReferral(address(vault), amount, receiver, address(0));
        vm.stopPrank();
    }

    function testDepositWithReferralRevertsOnZeroVault() external {
        vm.expectRevert("vault is not endorsed");
        wrapper.depositWithReferral(address(0), 1, receiver, referrer);
    }

    function testDepositWithReferralRevertsOnZeroAssets() external {
        token.mint(user, 1);
        vm.startPrank(user);
        IERC20(address(token)).approve(address(wrapper), 1);
        vm.expectRevert("cannot deposit zero");
        wrapper.depositWithReferral(address(vault), 0, receiver, referrer);
        vm.stopPrank();
    }

    function testDepositWithReferralRevertsOnMaxWhenBalanceZero() external {
        vm.startPrank(user);
        IERC20(address(token)).approve(address(wrapper), type(uint256).max);
        vm.expectRevert("cannot deposit zero");
        wrapper.depositWithReferral(address(vault), type(uint256).max, receiver, referrer);
        vm.stopPrank();
    }

    function testDepositWithReferralForceApprovePattern() external {
        MockERC20ForceApprove forceToken = new MockERC20ForceApprove("Force Token", "FORCE");
        MockVault forceVault = new MockVault(address(forceToken));
        YearnReferralDepositWrapper depositWrapper = new YearnReferralDepositWrapper();

        uint256 amount = 3e18;
        forceToken.mint(user, amount);

        vm.startPrank(user);
        IERC20(address(forceToken)).approve(address(depositWrapper), amount);
        // validate the approval worked
        assertEq(IERC20(address(forceToken)).allowance(user, address(depositWrapper)), amount);

        depositWrapper.depositWithReferral(address(forceVault), amount, receiver, referrer);
        vm.stopPrank();

        // validate the tokens were deposited and allowance is now zero
        assertEq(IERC20(address(forceToken)).balanceOf(address(forceVault)), amount);
        assertEq(IERC20(address(forceToken)).allowance(user, address(depositWrapper)), 0);
    }

    function testSweepTransfersToGovernance() external {
        uint256 amount = 7e18;
        token.mint(address(wrapper), amount);

        vm.prank(GOVERNANCE);
        wrapper.sweep(IERC20(address(token)));

        assertEq(IERC20(address(token)).balanceOf(address(wrapper)), 0);
        assertEq(IERC20(address(token)).balanceOf(GOVERNANCE), amount);
    }

    function testSweepRevertsWhenNotGovernance() external {
        token.mint(address(wrapper), 1e18);

        vm.prank(user);
        vm.expectRevert("Must be called by governance");
        wrapper.sweep(IERC20(address(token)));
    }
}
