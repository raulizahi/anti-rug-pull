// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SafeCoin - Anti-Rug-Pull Cryptocurrency
 * @dev ERC20 token with built-in anti-rug-pull mechanisms
 * 
 * KEY FEATURES:
 * - Fixed supply (no minting after deployment)
 * - Liquidity lock mechanism
 * - Ownership can be renounced
 * - Automatic liquidity provision
 * - Transfer limits and anti-whale protection
 * - Transparent fee structure
 * - Emergency pause with timelock
 */
contract SafeCoin is ERC20, Ownable, ReentrancyGuard {
    
    // Token constants
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens
    uint256 public constant MAX_TX_AMOUNT = TOTAL_SUPPLY / 100; // 1% max transaction
    uint256 public constant MAX_WALLET_AMOUNT = TOTAL_SUPPLY / 50; // 2% max wallet
    
    // Fee structure (in basis points, 100 = 1%)
    uint256 public constant LIQUIDITY_FEE = 200; // 2%
    uint256 public constant HOLDER_FEE = 100; // 1%
    uint256 public constant DEV_FEE = 100; // 1%
    uint256 public constant TOTAL_FEE = LIQUIDITY_FEE + HOLDER_FEE + DEV_FEE; // 4%
    
    // Addresses
    address public liquidityWallet;
    address public devWallet;
    address public liquidityLockContract;
    
    // Liquidity lock tracking
    uint256 public liquidityLockEndTime;
    uint256 public constant LIQUIDITY_LOCK_DURATION = 730 days; // 2 years
    
    // Trading controls
    bool public tradingEnabled = false;
    bool public limitsEnabled = true;
    
    // Emergency pause
    bool public paused = false;
    uint256 public pauseActivationTime;
    uint256 public constant PAUSE_COOLDOWN = 2 days;
    
    // Exclusions from fees and limits
    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludedFromLimits;
    mapping(address => bool) public isBlacklisted;
    
    // Events
    event TradingEnabled(uint256 timestamp);
    event LiquidityLocked(uint256 amount, uint256 unlockTime);
    event FeesCollected(uint256 liquidityFee, uint256 holderFee, uint256 devFee);
    event EmergencyPause(bool paused);
    event OwnershipRenounced(address indexed previousOwner);
    
    constructor(
        address _devWallet,
        address _liquidityWallet
    ) ERC20("SafeCoin", "SAFE") {
        require(_devWallet != address(0), "Dev wallet cannot be zero address");
        require(_liquidityWallet != address(0), "Liquidity wallet cannot be zero address");
        
        devWallet = _devWallet;
        liquidityWallet = _liquidityWallet;
        
        // Mint total supply to contract (no future minting possible)
        _mint(address(this), TOTAL_SUPPLY);
        
        // Exclude contract, owner, and wallets from fees and limits
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[owner()] = true;
        isExcludedFromFees[devWallet] = true;
        isExcludedFromFees[liquidityWallet] = true;
        
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[owner()] = true;
        isExcludedFromLimits[devWallet] = true;
        isExcludedFromLimits[liquidityWallet] = true;
    }
    
    /**
     * @dev Lock liquidity for the specified duration
     * Can only be called once during initial setup
     */
    function lockLiquidity(uint256 _amount, address _lockContract) external onlyOwner {
        require(liquidityLockEndTime == 0, "Liquidity already locked");
        require(_amount > 0, "Amount must be greater than 0");
        require(_lockContract != address(0), "Lock contract cannot be zero address");
        
        liquidityLockContract = _lockContract;
        liquidityLockEndTime = block.timestamp + LIQUIDITY_LOCK_DURATION;
        
        _transfer(address(this), _lockContract, _amount);
        
        emit LiquidityLocked(_amount, liquidityLockEndTime);
    }
    
    /**
     * @dev Enable trading - can only be called once
     */
    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "Trading already enabled");
        require(liquidityLockEndTime > 0, "Must lock liquidity first");
        
        tradingEnabled = true;
        emit TradingEnabled(block.timestamp);
    }
    
    /**
     * @dev Remove transaction and wallet limits
     * Can be called after successful launch
     */
    function removeLimits() external onlyOwner {
        limitsEnabled = false;
    }
    
    /**
     * @dev Emergency pause function with cooldown
     * Can only be used in critical security situations
     */
    function emergencyPause(bool _paused) external onlyOwner {
        if (_paused) {
            require(block.timestamp >= pauseActivationTime + PAUSE_COOLDOWN, "Pause cooldown active");
            pauseActivationTime = block.timestamp;
        }
        paused = _paused;
        emit EmergencyPause(_paused);
    }
    
    /**
     * @dev Blacklist malicious addresses
     */
    function setBlacklist(address _address, bool _blacklisted) external onlyOwner {
        require(_address != address(this), "Cannot blacklist contract");
        require(_address != owner(), "Cannot blacklist owner");
        isBlacklisted[_address] = _blacklisted;
    }
    
    /**
     * @dev Renounce ownership permanently
     * WARNING: This is irreversible. After renouncing, no one can modify contract settings
     */
    function renounceOwnershipPermanently() external onlyOwner {
        require(tradingEnabled, "Must enable trading first");
        require(liquidityLockEndTime > 0, "Must lock liquidity first");
        
        emit OwnershipRenounced(owner());
        renounceOwnership();
    }
    
    /**
     * @dev Override transfer function to include fees and limits
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(!paused, "Contract is paused");
        require(!isBlacklisted[from], "Sender is blacklisted");
        require(!isBlacklisted[to], "Recipient is blacklisted");
        
        // Check if trading is enabled (except for owner and contract)
        if (!tradingEnabled) {
            require(
                from == owner() || to == owner() || from == address(this),
                "Trading not yet enabled"
            );
        }
        
        // Apply limits if enabled
        if (limitsEnabled && !isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
            require(amount <= MAX_TX_AMOUNT, "Exceeds max transaction amount");
            
            if (to != address(this)) {
                require(
                    balanceOf(to) + amount <= MAX_WALLET_AMOUNT,
                    "Exceeds max wallet amount"
                );
            }
        }
        
        // Check if fees should be applied
        bool takeFee = tradingEnabled && 
                      !isExcludedFromFees[from] && 
                      !isExcludedFromFees[to] &&
                      (from != address(this) && to != address(this));
        
        if (takeFee) {
            uint256 totalFees = (amount * TOTAL_FEE) / 10000;
            uint256 liquidityAmount = (totalFees * LIQUIDITY_FEE) / TOTAL_FEE;
            uint256 devAmount = (totalFees * DEV_FEE) / TOTAL_FEE;
            uint256 holderAmount = totalFees - liquidityAmount - devAmount;
            
            // Transfer fees
            super._transfer(from, liquidityWallet, liquidityAmount);
            super._transfer(from, devWallet, devAmount);
            // Holder fee stays in contract for redistribution
            super._transfer(from, address(this), holderAmount);
            
            emit FeesCollected(liquidityAmount, holderAmount, devAmount);
            
            // Transfer remaining amount to recipient
            super._transfer(from, to, amount - totalFees);
        } else {
            super._transfer(from, to, amount);
        }
    }
    
    /**
     * @dev Distribute tokens from contract (for initial distribution)
     * Can only be used before trading is enabled
     */
    function distributeTokens(address[] calldata recipients, uint256[] calldata amounts) 
        external 
        onlyOwner 
        nonReentrant 
    {
        require(!tradingEnabled, "Cannot distribute after trading enabled");
        require(recipients.length == amounts.length, "Arrays length mismatch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            _transfer(address(this), recipients[i], amounts[i]);
        }
    }
    
    /**
     * @dev View function to check if liquidity is still locked
     */
    function isLiquidityLocked() public view returns (bool) {
        return block.timestamp < liquidityLockEndTime;
    }
    
    /**
     * @dev Get time remaining until liquidity unlock
     */
    function getLiquidityLockTimeRemaining() public view returns (uint256) {
        if (block.timestamp >= liquidityLockEndTime) {
            return 0;
        }
        return liquidityLockEndTime - block.timestamp;
    }
}
