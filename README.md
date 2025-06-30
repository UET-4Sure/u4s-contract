# NolaSwap - Compliant DEX Built on Uniswap v4

NolaSwap is a decentralized exchange (DEX) built on Uniswap v4, focusing on regulatory compliance while maintaining decentralization and privacy. This implementation includes advanced features for KYC/AML, automated tax collection, and MEV protection.

## Technical Architecture

### Core Contracts

1. **KYCContract.sol**
   - Manages KYC verification and volume restrictions
   - Implements tiered trading limits based on KYC level
   - Uses Chainlink price feeds for volume calculations
   - Features:
     - Volume-based KYC requirements
     - Token and user restriction capabilities
     - Configurable trading limits for swaps and liquidity operations

2. **MainHook.sol**
   - Core hook implementation for Uniswap v4
   - Handles swap validation and liquidity management
   - Integrates with KYC and Tax contracts
   - Key features:
     - Pre-swap validation
     - Liquidity position management
     - MEV protection mechanisms

3. **TaxContract.sol**
   - Manages automated tax collection
   - Configurable tax rates and whitelisting
   - Transparent on-chain tax storage
   - Features:
     - Automated 0.1% tax collection
     - Whitelist management
     - Tax withdrawal mechanisms
     - Support for both ERC20 and native currency

4. **MEVArbitrage.sol**
   - Implements MEV protection mechanisms
   - Features:
     - Price commitment mechanism
     - Liquidity rebalancing
     - Arbitrage control
     - Protection against sandwich attacks

## Key Technical Features

### Identity Verification
- SoulBound Token (SBT) based identity verification
- Three-tier KYC system with different trading limits
- Privacy-preserving verification mechanism

### Trading Protection
```solidity
function isPermitKYCSwap(uint256 amount, address token) public view returns (bool)
function isPermitKYCModifyLiquidity(uint256 amount0, address token0, uint256 amount1, address token1) public view returns (bool)
```
- Volume-based trading restrictions
- Smart anti-money laundering checks
- Real-time price feed integration

### Tax Management
```solidity
function calculateTax(uint256 amount) external view returns (uint256)
function withdrawERC20(address token, uint256 amount) external
```
- Automated tax collection system
- Transparent tax storage
- Configurable tax rates
- Support for multiple tokens

### MEV Protection
```solidity
function openPool(uint160 _newSqrtPriceX96) external
function depositHedgeCommitment(uint256 amount0, uint256 amount1) external payable
```
- Price commitment mechanism
- Liquidity provider protection
- Anti-sandwich attack measures
- Fair ordering system

## Technical Requirements

- Solidity ^0.8.24
- Uniswap v4 Core
- OpenZeppelin Contracts
- Chainlink Price Feeds

## Development Setup

1. Clone the repository
```bash
git clone https://github.com/your-repo/nolaswap.git
```

2. Install dependencies
```bash
forge install
```

3. Compile contracts
```bash
forge build
```

4. Run tests
```bash
forge test
```

## Security Considerations

1. **Access Control**
   - Ownable pattern for administrative functions
   - Role-based access control for sensitive operations
   - Whitelisting mechanism for privileged operations

2. **Price Oracle Security**
   - Chainlink price feed integration
   - Fallback mechanisms for oracle failures
   - Price manipulation protection

3. **Smart Contract Safety**
   - Reentrancy protection
   - Integer overflow protection (Solidity ^0.8.x)
   - Emergency pause functionality

## License

MIT License

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.

## Audits

[Pending - Security audits will be conducted before mainnet deployment]

