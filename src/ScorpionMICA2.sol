// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// 引入 Chainlink 预言机接口
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/**
 * @title ScorpionMICA2
 * @dev 接入 Chainlink 预言机，确保储备金（ETH）足额抵押后才允许铸造
 */
contract ScorpionMICA2 is 
    Initializable, 
    ERC20Upgradeable, 
    ERC20PausableUpgradeable, 
    AccessControlUpgradeable, 
    UUPSUpgradeable 
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // --- MiCA 合规变量 ---
    mapping(address => bool) public isBlacklisted;
    uint256 public maxSupply; 

    // --- 预言机与抵押品变量 ---
    AggregatorV3Interface internal priceFeed;
    // 要求的抵押率，例如 100 代表 100%（1:1），120 代表 120% 超额抵押
    uint256 public minCollateralRatio; 

    event Blacklisted(address indexed account, bool status);
    event FundsWiped(address indexed account, uint256 amount);
    event CollateralRatioUpdated(uint256 newRatio);
    event MaxSupplyUpdated(uint256 oldCap, uint256 newCap);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @param _priceFeed Chainlink ETH/USD 地址
     * 常用地址 (Sepolia 测试网): 0x694AA1769357215DE4FAC081bf1f309aDC325306
     */
    function initialize(
        address admin, 
        uint256 initialSupply, 
        uint256 cap,
        address _priceFeed
    ) public initializer {
        __ERC20_init(unicode"蝎币 MICA版 2", "SCORPMICA2");
        __ERC20Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        maxSupply = cap;
        minCollateralRatio = 100; // 默认 100% 抵押
        priceFeed = AggregatorV3Interface(_priceFeed);

        _mint(admin, initialSupply * 10 ** decimals());
    }

    // ========== 核心逻辑：储备金验证 ==========

    /**
     * @dev 获取最新的 ETH 价格 (USD)
     * Chainlink ETH/USD 返回 8 位小数
     */
    function getLatestPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Oracle: Invalid price");
        return uint256(price);
    }

    /**
     * @dev 计算当前储备金（合约内的 ETH 余额）的总价值 (USD)
     * 返回结果带有 18 位小数（为了与 ERC20 对齐）
     */
    function getReserveValue() public view returns (uint256) {
        uint256 ethBalance = address(this).balance; // 获取合约持有的 ETH 数量
        uint256 ethPrice = getLatestPrice();        // 8 位小数
        
        // ethBalance(18位) * ethPrice(8位) / 10^8 = 18位小数的价值
        return (ethBalance * ethPrice) / 1e8;
    }

    // ========== 修改后的 Mint 函数 ==========

    /**
     * @dev 铸造代币前必须检查储备金价值是否覆盖了 (当前总量 + 待铸造量)
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        // 1. 检查硬上限
        require(totalSupply() + amount <= maxSupply, "MiCA: Exceeds max supply cap");

        // 2. 检查储备金是否充足
        uint256 totalNeededValue = (totalSupply() + amount) * minCollateralRatio / 100;
        uint256 currentReserveValue = getReserveValue();

        require(
            currentReserveValue >= totalNeededValue, 
            string(abi.encodePacked("MiCA: Insufficient reserves. Need: ", _uint2String(totalNeededValue), " USD"))
        );

        _mint(to, amount);
    }

    // ========== 管理功能 ==========

    /**
     * @dev 更新抵押率要求
     */
    function setMinCollateralRatio(uint256 _ratio) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_ratio >= 100, "MiCA: Ratio must be at least 100%");
        minCollateralRatio = _ratio;
        emit CollateralRatioUpdated(_ratio);
    }

    /**
     * @dev 更新供应量上限（带 18 位小数）
     */
    function setMaxSupply(uint256 newCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newCap >= totalSupply(), "MiCA: Cap below current supply");
        emit MaxSupplyUpdated(maxSupply, newCap);
        maxSupply = newCap;
    }

    /**
     * @dev 允许合约接收 ETH 作为抵押品
     */
    receive() external payable {}

    // ========== 原有功能保持不变 ==========

    function _update(address from, address to, uint256 amount) 
        internal 
        override(ERC20Upgradeable, ERC20PausableUpgradeable) 
    {
        if (to != address(0)) {
            if (from != address(0)) {
                require(!isBlacklisted[from], "MiCA: sender is blacklisted");
            }
            require(!isBlacklisted[to], "MiCA: recipient is blacklisted");
        }
        super._update(from, to, amount);
    }

    function setBlacklist(address account, bool status) external onlyRole(COMPLIANCE_ROLE) {
        isBlacklisted[account] = status;
        emit Blacklisted(account, status);
    }

    function wipeBlacklistedFunds(address account) external onlyRole(COMPLIANCE_ROLE) {
        require(isBlacklisted[account], "MiCA: Account not blacklisted");
        uint256 balance = balanceOf(account);
        _burn(account, balance);
        emit FundsWiped(account, balance);
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // 辅助函数：数值转字符串（用于报错信息）
    function _uint2String(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bstr[k] = bytes1(temp);
            _i /= 10;
        }
        return string(bstr);
    }
}