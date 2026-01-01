# SafeCoin Deployment Guide

## Prerequisites

- Node.js v16+ installed
- Hardhat or Truffle framework
- Ethereum wallet with ETH for gas fees
- Access to Ethereum mainnet or testnet RPC

## Installation

```bash
npm install --save-dev hardhat
npm install @openzeppelin/contracts
npm install @nomiclabs/hardhat-ethers ethers
```

## Deployment Steps

### 1. Prepare Environment

Create a `.env` file:
```
PRIVATE_KEY=your_private_key_here
ETHERSCAN_API_KEY=your_etherscan_api_key
MAINNET_RPC_URL=your_rpc_url
```

### 2. Configure Hardhat

Create `hardhat.config.js`:
```javascript
require('@nomiclabs/hardhat-ethers');
require('@nomiclabs/hardhat-etherscan');
require('dotenv').config();

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    mainnet: {
      url: process.env.MAINNET_RPC_URL,
      accounts: [process.env.PRIVATE_KEY]
    },
    goerli: {
      url: process.env.GOERLI_RPC_URL,
      accounts: [process.env.PRIVATE_KEY]
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};
```

### 3. Create Deployment Script

Create `scripts/deploy.js`:
```javascript
const hre = require("hardhat");

async function main() {
  console.log("Deploying SafeCoin...");
  
  // Set wallet addresses
  const devWallet = "0x..."; // Replace with actual dev wallet
  const liquidityWallet = "0x..."; // Replace with actual liquidity wallet
  
  // Deploy contract
  const SafeCoin = await hre.ethers.getContractFactory("SafeCoin");
  const safeCoin = await SafeCoin.deploy(devWallet, liquidityWallet);
  
  await safeCoin.deployed();
  
  console.log("SafeCoin deployed to:", safeCoin.address);
  console.log("Dev Wallet:", devWallet);
  console.log("Liquidity Wallet:", liquidityWallet);
  
  // Wait for block confirmations
  console.log("Waiting for block confirmations...");
  await safeCoin.deployTransaction.wait(6);
  
  // Verify on Etherscan
  console.log("Verifying contract on Etherscan...");
  await hre.run("verify:verify", {
    address: safeCoin.address,
    constructorArguments: [devWallet, liquidityWallet],
  });
  
  console.log("Deployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

### 4. Deploy to Testnet (Recommended First)

```bash
npx hardhat run scripts/deploy.js --network goerli
```

### 5. Post-Deployment Setup

After deployment, execute these functions in order:

#### A. Distribute Initial Tokens
```javascript
// Distribute tokens to early supporters, airdrop recipients, etc.
await safeCoin.distributeTokens(
  [address1, address2, address3],
  [amount1, amount2, amount3]
);
```

#### B. Add Liquidity to DEX
1. Add liquidity on Uniswap/PancakeSwap
2. Receive LP tokens
3. Send LP tokens to time-lock contract

#### C. Lock Liquidity
```javascript
// Lock liquidity for 2 years
await safeCoin.lockLiquidity(liquidityAmount, lockContractAddress);
```

#### D. Enable Trading
```javascript
await safeCoin.enableTrading();
```

#### E. Renounce Ownership (FINAL STEP)
```javascript
// WARNING: This is irreversible!
await safeCoin.renounceOwnershipPermanently();
```

## Liquidity Lock Contract

You'll need a separate time-lock contract. Here's a simple example:

```solidity
// SimpleLiquidityLock.sol
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleLiquidityLock {
    address public token;
    address public beneficiary;
    uint256 public releaseTime;
    
    constructor(address _token, address _beneficiary, uint256 _releaseTime) {
        require(_releaseTime > block.timestamp, "Release time must be in future");
        token = _token;
        beneficiary = _beneficiary;
        releaseTime = _releaseTime;
    }
    
    function release() external {
        require(block.timestamp >= releaseTime, "Tokens still locked");
        require(msg.sender == beneficiary, "Only beneficiary can release");
        
        uint256 amount = IERC20(token).balanceOf(address(this));
        require(amount > 0, "No tokens to release");
        
        IERC20(token).transfer(beneficiary, amount);
    }
    
    function getTimeUntilRelease() external view returns (uint256) {
        if (block.timestamp >= releaseTime) return 0;
        return releaseTime - block.timestamp;
    }
}
```

## Security Checklist

Before mainnet deployment:

- [ ] Test all functions on testnet thoroughly
- [ ] Get professional smart contract audit (CertiK, OpenZeppelin, etc.)
- [ ] Verify contract source code on Etherscan
- [ ] Test liquidity lock mechanism
- [ ] Test emergency pause functionality
- [ ] Verify all wallet addresses are correct
- [ ] Test token distribution
- [ ] Verify max transaction and wallet limits work
- [ ] Test trading enable/disable
- [ ] Document all admin functions used
- [ ] Create multi-sig wallet for dev funds
- [ ] Set up monitoring for contract events
- [ ] Prepare communication plan for community
- [ ] Have emergency response plan ready

## Post-Launch Monitoring

1. Monitor contract on Etherscan
2. Track liquidity pool health
3. Watch for unusual transactions
4. Monitor holder distribution
5. Track volume and price action
6. Respond to community questions
7. Publish transparency reports

## Recommended Tools

- **Etherscan**: Contract verification and monitoring
- **DexTools**: Trading analytics
- **Uniswap Info**: Liquidity tracking
- **Gnosis Safe**: Multi-sig wallet for team funds
- **CoinGecko/CoinMarketCap**: Listing applications
- **Discord/Telegram**: Community management

## Cost Estimates

- Contract deployment: ~0.05-0.1 ETH (varies with gas)
- Contract verification: Free
- Adding liquidity: ~0.01-0.03 ETH
- Professional audit: $5,000-$20,000
- Marketing/listings: Variable

## Important Notes

⚠️ **WARNING**: Once you renounce ownership, you CANNOT:
- Change any contract parameters
- Pause trading (except emergency pause if not renounced)
- Modify fee structure
- Mint new tokens
- Recover tokens sent to contract by mistake

✅ This is by design to prevent rug pulls, but means you must be absolutely certain everything is configured correctly before renouncing.

## Support Resources

- OpenZeppelin Documentation: https://docs.openzeppelin.com/
- Hardhat Documentation: https://hardhat.org/
- Etherscan API: https://docs.etherscan.io/
- Uniswap V2 Docs: https://docs.uniswap.org/

## Legal Disclaimer

This code is provided as-is for educational purposes. Deploying a cryptocurrency involves significant legal, financial, and technical risks. Consult with legal counsel regarding securities laws, tax implications, and regulatory compliance in your jurisdiction before launching.
