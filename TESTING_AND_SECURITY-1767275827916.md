# SafeCoin Testing Guide & Security Audit Checklist

## Automated Testing Suite

### Setup Test Environment

Create `test/SafeCoin.test.js`:

```javascript
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("SafeCoin", function () {
  let safeCoin;
  let owner, devWallet, liquidityWallet, user1, user2;
  
  beforeEach(async function () {
    [owner, devWallet, liquidityWallet, user1, user2] = await ethers.getSigners();
    
    const SafeCoin = await ethers.getContractFactory("SafeCoin");
    safeCoin = await SafeCoin.deploy(devWallet.address, liquidityWallet.address);
    await safeCoin.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await safeCoin.owner()).to.equal(owner.address);
    });

    it("Should assign total supply to contract", async function () {
      const totalSupply = await safeCoin.totalSupply();
      expect(await safeCoin.balanceOf(safeCoin.address)).to.equal(totalSupply);
    });

    it("Should set correct dev and liquidity wallets", async function () {
      expect(await safeCoin.devWallet()).to.equal(devWallet.address);
      expect(await safeCoin.liquidityWallet()).to.equal(liquidityWallet.address);
    });
  });

  describe("Anti-Rug-Pull Features", function () {
    it("Should prevent trading before enabled", async function () {
      await safeCoin.distributeTokens([user1.address], [1000]);
      await expect(
        safeCoin.connect(user1).transfer(user2.address, 500)
      ).to.be.revertedWith("Trading not yet enabled");
    });

    it("Should lock liquidity correctly", async function () {
      const lockAmount = ethers.utils.parseEther("100000");
      const mockLockContract = user1.address; // Using address as mock
      
      await safeCoin.lockLiquidity(lockAmount, mockLockContract);
      
      expect(await safeCoin.isLiquidityLocked()).to.equal(true);
      expect(await safeCoin.balanceOf(mockLockContract)).to.equal(lockAmount);
    });

    it("Should prevent double liquidity lock", async function () {
      const lockAmount = ethers.utils.parseEther("100000");
      await safeCoin.lockLiquidity(lockAmount, user1.address);
      
      await expect(
        safeCoin.lockLiquidity(lockAmount, user1.address)
      ).to.be.revertedWith("Liquidity already locked");
    });

    it("Should require liquidity lock before enabling trading", async function () {
      await expect(
        safeCoin.enableTrading()
      ).to.be.revertedWith("Must lock liquidity first");
    });

    it("Should enable trading only once", async function () {
      await safeCoin.lockLiquidity(ethers.utils.parseEther("100000"), user1.address);
      await safeCoin.enableTrading();
      
      await expect(
        safeCoin.enableTrading()
      ).to.be.revertedWith("Trading already enabled");
    });
  });

  describe("Transaction Limits", function () {
    beforeEach(async function () {
      await safeCoin.lockLiquidity(ethers.utils.parseEther("100000"), user1.address);
      await safeCoin.enableTrading();
      
      const distributeAmount = ethers.utils.parseEther("50000000");
      await safeCoin.distributeTokens([user1.address], [distributeAmount]);
    });

    it("Should enforce max transaction limit", async function () {
      const maxTx = await safeCoin.MAX_TX_AMOUNT();
      const overLimit = maxTx.add(1);
      
      await expect(
        safeCoin.connect(user1).transfer(user2.address, overLimit)
      ).to.be.revertedWith("Exceeds max transaction amount");
    });

    it("Should enforce max wallet limit", async function () {
      const maxWallet = await safeCoin.MAX_WALLET_AMOUNT();
      const overLimit = maxWallet.add(1);
      
      await expect(
        safeCoin.connect(user1).transfer(user2.address, overLimit)
      ).to.be.revertedWith("Exceeds max wallet amount");
    });

    it("Should allow removing limits", async function () {
      await safeCoin.removeLimits();
      expect(await safeCoin.limitsEnabled()).to.equal(false);
      
      // Should now allow large transfers
      const largeAmount = ethers.utils.parseEther("30000000");
      await expect(
        safeCoin.connect(user1).transfer(user2.address, largeAmount)
      ).to.not.be.reverted;
    });
  });

  describe("Fee Mechanism", function () {
    beforeEach(async function () {
      await safeCoin.lockLiquidity(ethers.utils.parseEther("100000"), user1.address);
      await safeCoin.enableTrading();
      
      const distributeAmount = ethers.utils.parseEther("10000000");
      await safeCoin.distributeTokens([user1.address], [distributeAmount]);
    });

    it("Should apply fees on transfers", async function () {
      const transferAmount = ethers.utils.parseEther("1000");
      const totalFee = await safeCoin.TOTAL_FEE();
      const expectedFees = transferAmount.mul(totalFee).div(10000);
      const expectedReceived = transferAmount.sub(expectedFees);
      
      await safeCoin.connect(user1).transfer(user2.address, transferAmount);
      
      expect(await safeCoin.balanceOf(user2.address)).to.equal(expectedReceived);
    });

    it("Should distribute fees correctly", async function () {
      const transferAmount = ethers.utils.parseEther("1000");
      
      const devBalanceBefore = await safeCoin.balanceOf(devWallet.address);
      const liquidityBalanceBefore = await safeCoin.balanceOf(liquidityWallet.address);
      
      await safeCoin.connect(user1).transfer(user2.address, transferAmount);
      
      const devBalanceAfter = await safeCoin.balanceOf(devWallet.address);
      const liquidityBalanceAfter = await safeCoin.balanceOf(liquidityWallet.address);
      
      expect(devBalanceAfter).to.be.gt(devBalanceBefore);
      expect(liquidityBalanceAfter).to.be.gt(liquidityBalanceBefore);
    });

    it("Should not apply fees to excluded addresses", async function () {
      const transferAmount = ethers.utils.parseEther("1000");
      
      // Transfer from contract (excluded)
      await safeCoin.transfer(user2.address, transferAmount);
      
      expect(await safeCoin.balanceOf(user2.address)).to.equal(transferAmount);
    });
  });

  describe("Security Features", function () {
    it("Should allow emergency pause", async function () {
      await safeCoin.emergencyPause(true);
      expect(await safeCoin.paused()).to.equal(true);
      
      await expect(
        safeCoin.transfer(user1.address, 1000)
      ).to.be.revertedWith("Contract is paused");
    });

    it("Should enforce pause cooldown", async function () {
      await safeCoin.emergencyPause(true);
      await safeCoin.emergencyPause(false);
      
      await expect(
        safeCoin.emergencyPause(true)
      ).to.be.revertedWith("Pause cooldown active");
    });

    it("Should blacklist addresses", async function () {
      await safeCoin.setBlacklist(user1.address, true);
      
      await expect(
        safeCoin.transfer(user1.address, 1000)
      ).to.be.revertedWith("Recipient is blacklisted");
    });

    it("Should allow ownership renouncement after setup", async function () {
      await safeCoin.lockLiquidity(ethers.utils.parseEther("100000"), user1.address);
      await safeCoin.enableTrading();
      
      await safeCoin.renounceOwnershipPermanently();
      
      expect(await safeCoin.owner()).to.equal(ethers.constants.AddressZero);
    });

    it("Should prevent renouncement before setup complete", async function () {
      await expect(
        safeCoin.renounceOwnershipPermanently()
      ).to.be.revertedWith("Must enable trading first");
    });
  });

  describe("Token Distribution", function () {
    it("Should distribute tokens before trading", async function () {
      const amount = ethers.utils.parseEther("1000");
      await safeCoin.distributeTokens([user1.address, user2.address], [amount, amount]);
      
      expect(await safeCoin.balanceOf(user1.address)).to.equal(amount);
      expect(await safeCoin.balanceOf(user2.address)).to.equal(amount);
    });

    it("Should prevent distribution after trading enabled", async function () {
      await safeCoin.lockLiquidity(ethers.utils.parseEther("100000"), user1.address);
      await safeCoin.enableTrading();
      
      await expect(
        safeCoin.distributeTokens([user1.address], [1000])
      ).to.be.revertedWith("Cannot distribute after trading enabled");
    });
  });
});
```

### Run Tests

```bash
npx hardhat test
npx hardhat coverage
```

## Manual Testing Checklist

### Pre-Deployment Testing

- [ ] Test on local Hardhat network
- [ ] Test on public testnet (Goerli/Sepolia)
- [ ] Verify all constructor parameters
- [ ] Test initial token distribution
- [ ] Test liquidity lock mechanism
- [ ] Test trading enable function
- [ ] Test all fee calculations
- [ ] Test transfer limits (max tx, max wallet)
- [ ] Test blacklist functionality
- [ ] Test emergency pause
- [ ] Test ownership renouncement
- [ ] Verify contract events emission

### Post-Deployment Testing

- [ ] Verify contract on Etherscan
- [ ] Test buy transactions on DEX
- [ ] Test sell transactions on DEX
- [ ] Verify fees are collected correctly
- [ ] Check liquidity lock status
- [ ] Monitor gas costs
- [ ] Test with multiple wallets
- [ ] Verify max transaction enforcement
- [ ] Verify max wallet enforcement

## Security Audit Checklist

### Smart Contract Security

#### Access Control
- [ ] Owner functions properly restricted
- [ ] Critical functions cannot be called by unauthorized addresses
- [ ] Ownership transfer mechanism secure
- [ ] Ownership renouncement works correctly
- [ ] No backdoors for minting tokens
- [ ] No hidden admin functions

#### Liquidity Protection
- [ ] Liquidity lock cannot be bypassed
- [ ] Lock duration is enforced
- [ ] Cannot withdraw locked liquidity early
- [ ] Lock contract address cannot be changed after set
- [ ] Trading cannot be enabled before liquidity lock

#### Transfer Logic
- [ ] No overflow/underflow vulnerabilities
- [ ] Reentrancy protection in place
- [ ] Transfer fees calculated correctly
- [ ] Fee distribution working as intended
- [ ] No way to bypass transfer fees
- [ ] Excluded addresses list cannot be abused

#### Anti-Whale Mechanisms
- [ ] Max transaction limit enforced
- [ ] Max wallet limit enforced
- [ ] Limits can be removed by owner
- [ ] Excluded addresses properly managed
- [ ] No way to circumvent limits through multiple transactions

#### Emergency Controls
- [ ] Emergency pause has cooldown
- [ ] Pause cannot be abused
- [ ] Blacklist function works correctly
- [ ] Cannot blacklist critical addresses
- [ ] Emergency functions cannot be used maliciously

#### Token Economics
- [ ] Total supply is fixed (no minting)
- [ ] No burn function that could be abused
- [ ] Initial distribution is fair
- [ ] No hidden token allocations
- [ ] Fee percentages are reasonable

### Code Quality

- [ ] Uses latest stable Solidity version
- [ ] Inherits from audited OpenZeppelin contracts
- [ ] No use of deprecated functions
- [ ] Proper error messages
- [ ] Events emitted for important state changes
- [ ] Code is well-commented
- [ ] Gas optimization applied where appropriate

### External Dependencies

- [ ] OpenZeppelin contracts version verified
- [ ] No malicious dependencies
- [ ] All imports from trusted sources
- [ ] Compatible with standard wallets and DEXs
- [ ] ERC20 standard fully implemented

### Front-Running Protection

- [ ] No vulnerable ordering dependencies
- [ ] MEV exploitation potential minimized
- [ ] Slippage protection for users

### Known Attack Vectors

- [ ] Protected against reentrancy attacks
- [ ] No integer overflow/underflow
- [ ] No front-running vulnerabilities
- [ ] No flash loan attack vectors
- [ ] Protected against sandwich attacks
- [ ] No honeypot characteristics

### Centralization Risks

- [ ] Owner powers are limited and temporary
- [ ] Ownership renouncement mechanism works
- [ ] No single point of failure after renouncement
- [ ] Decentralized from launch

## Professional Audit Recommendations

### Recommended Audit Firms

1. **OpenZeppelin** - Industry standard, comprehensive audits
2. **CertiK** - Formal verification and security analysis
3. **Trail of Bits** - Deep security expertise
4. **ConsenSys Diligence** - Ethereum-focused auditing
5. **Hacken** - Affordable option for smaller projects

### Audit Process

1. Complete internal testing first
2. Fix all known issues
3. Freeze code (no changes during audit)
4. Provide audit firm with:
   - Source code
   - Documentation
   - Test suite
   - Deployment plan
5. Address all findings
6. Re-audit if critical issues found
7. Publish audit report publicly

### Cost-Benefit Analysis

- Small project (< $100k raise): Consider CertiK or Hacken ($5-10k)
- Medium project ($100k-$1M raise): OpenZeppelin or Trail of Bits ($15-30k)
- Large project (> $1M raise): Multiple audits recommended ($50k+)

## Bug Bounty Program

Consider launching a bug bounty program:

1. Set up on Immunefi or HackenProof
2. Offer rewards for vulnerability discovery
3. Typical rewards: $1k-$50k based on severity
4. Covers smart contract and infrastructure
5. Helps find issues after launch

## Continuous Monitoring

Post-launch monitoring tools:

- **Forta**: Real-time threat detection
- **OpenZeppelin Defender**: Automated security monitoring
- **Tenderly**: Transaction monitoring and alerting
- **Dune Analytics**: On-chain analytics dashboard

## Red Flags to Avoid

Your token SHOULD NOT have any of these:

- ❌ Hidden mint function
- ❌ Ability to change fees after launch
- ❌ Ability to pause trading indefinitely
- ❌ Owner can withdraw liquidity
- ❌ Blacklist function that can ban anyone anytime
- ❌ Modifiable max transaction limits
- ❌ Hidden backdoors in code
- ❌ Unaudited code
- ❌ Anonymous team with full control
- ❌ No liquidity lock

Your token SHOULD have:

- ✅ Fixed supply
- ✅ Locked liquidity (2+ years)
- ✅ Renounced or multi-sig ownership
- ✅ Transparent fees
- ✅ Professional audit
- ✅ Verified source code
- ✅ Clear documentation
- ✅ Anti-whale limits
- ✅ Fair distribution
- ✅ Active community

## Final Security Checklist Before Launch

- [ ] All tests passing
- [ ] Professional audit completed and published
- [ ] Contract verified on Etherscan
- [ ] Liquidity locked with proof
- [ ] Initial distribution completed fairly
- [ ] Trading enabled
- [ ] Ownership renounced
- [ ] Documentation published
- [ ] Community informed
- [ ] Monitoring tools active
- [ ] Emergency response plan ready
- [ ] Legal compliance checked
- [ ] Marketing materials accurate
- [ ] No misleading claims
- [ ] Team identified (or fully anonymous with reasons)

Remember: A secure launch builds trust and long-term success. Don't rush to market without proper testing and auditing.
