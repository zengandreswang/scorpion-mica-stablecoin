// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/ScorpionMICA2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ScorpionTest is Test {
    ScorpionMICA2 public token;
    address admin = address(1);
    // Sepolia ETH/USD 预言机地址
    address ethUsdPriceFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    function setUp() public {
        // 1. 部署逻辑合约
        ScorpionMICA2 implementation = new ScorpionMICA2();

        // 2. 编码初始化数据 (创世铸造 100 个代币，设置 100 万上限并带 18 位小数)
        bytes memory initData = abi.encodeWithSelector(
            ScorpionMICA2.initialize.selector,
            admin,
            100,
            1000000 * 1e18, 
            ethUsdPriceFeed
        );

        // 3. 通过代理合约进行部署与初始化
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        // 4. 将 token 变量指向代理合约
        token = ScorpionMICA2(payable(address(proxy)));
    }

    // ========== 1. 原有核心业务测试 ==========

    // 核心 MiCA 规则测试：在合约没有 ETH 储备的情况下，铸造必须被拦截
    function testMintFailsWithoutCollateral() public {
        vm.prank(admin);
        vm.expectRevert(); // 预期会报错，因为合约储备金价值为 0
        token.mint(admin, 100 * 1e18);
    }

    // ========== 2. 新增上限管理测试 ==========

    // 测试 A：管理员可以成功修改上限
    function test_SetMaxSupply_Success() public {
        uint256 newCap = 2000000 * 1e18; // 设为 200 万个
        
        vm.prank(admin);
        token.setMaxSupply(newCap);

        assertEq(token.maxSupply(), newCap);
    }

    // 测试 B：非管理员修改上限必须被拦截
    function test_SetMaxSupply_RevertIfNotAdmin() public {
        address hacker = address(0x999);
        uint256 newCap = 2000000 * 1e18;

        vm.prank(hacker);
        vm.expectRevert(); // 预期报错
        token.setMaxSupply(newCap);
    }

    // 测试 C：新上限不能低于当前已发行的总量 (100 个)
    function test_SetMaxSupply_RevertIfBelowTotalSupply() public {
        uint256 invalidCap = 50 * 1e18; // 50 < 100，非法值

        vm.prank(admin);
        vm.expectRevert("MiCA: Cap below current supply");
        token.setMaxSupply(invalidCap);
    }
}