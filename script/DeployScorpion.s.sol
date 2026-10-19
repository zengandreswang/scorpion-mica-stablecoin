// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/ScorpionMICA2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScorpion is Script {
    // Sepolia 测试网 Chainlink ETH/USD PriceFeed 官方地址
    address constant SEPOLIA_ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    function run() external {
        // 从 .env 加载部署者私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address adminAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // --- 第一步：部署逻辑合约 (Implementation) ---
        ScorpionMICA2 implementation = new ScorpionMICA2();
        console.log("1. Implementation deployed at:", address(implementation));

        // --- 第二步：准备初始化数据 (与最新版 ScorpionMICA2.sol 严格对齐) ---
        uint256 initialSupply = 100;             // 内部自动乘 10**decimals()，即创世铸造 100 枚
        uint256 maxSupplyCap = 1000000 * 1e18;   // 必须带 18 位小数：硬上限设为 100 万枚

        bytes memory initData = abi.encodeWithSelector(
            ScorpionMICA2.initialize.selector,
            adminAddress,
            initialSupply,
            maxSupplyCap,
            SEPOLIA_ETH_USD_FEED
        );

        // --- 第三步：部署 ERC1967 代理合约 (UUPS Proxy) ---
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        ScorpionMICA2 token = ScorpionMICA2(payable(address(proxy)));
        
        console.log("2. Proxy (Token Address) deployed at:", address(token));
        console.log("   -> Token Name:", token.name());
        console.log("   -> Initial Total Supply (wei):", token.totalSupply());
        console.log("   -> Max Supply Cap (wei):", token.maxSupply());
        console.log("   -> Min Collateral Ratio (%):", token.minCollateralRatio());

        vm.stopBroadcast();
    }
}