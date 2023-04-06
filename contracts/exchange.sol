// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = 'Ryan DEX';

    address tokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    Token public token = Token(tokenAddr);                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    mapping(address => uint) private lps; 
     
    // Needed for looping through the keys of the lps mapping
    address[] private lp_providers;                     

    // liquidity rewards
    uint private swap_fee_numerator = 3;                
    uint private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint private k;

    // decimals
    uint private share_denominator = 1000; 

    constructor() {}
    

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");

        // same owner of Token contract deployed with initial tokens minted
        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;
    }

    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    
    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    // @param exchange rate: represent the ratio of token_reserves / eth_reserves, which is usually greater than 1 
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate, uint rate_denominator) 
        external 
        payable
    {
        uint eth_amount = msg.value;
        require(eth_amount > 0, "Eth to add liquidity must be greater than 0.");

        // calculate token_amount first to avoid underflow
        uint token_amount = eth_amount * token_reserves / eth_reserves ;
        require(token_amount <= token.balanceOf(msg.sender), "Your token amount is not sufficient to add liquidity."); 

        require(token_reserves * rate_denominator >= eth_reserves * min_exchange_rate, "Slippage exceeds min threshold.");
        require(token_reserves * rate_denominator <= eth_reserves * max_exchange_rate, "Slippage exceeds max threshold.");

        // transfer token from user to exchange contract address
        token.transferFrom(msg.sender, address(this), token_amount);
        
        // update contract states
        uint prev_token_reserves = token_reserves;
        token_reserves = token.balanceOf(address(this));
        eth_reserves = address(this).balance;
        k = token_reserves * eth_reserves;

        // update shares of liquidity providers
        lps[msg.sender] = (lps[msg.sender] * prev_token_reserves + token_amount * share_denominator) / token_reserves; // share of current provider, regardless of whether they have joined before
        
        bool providerJoined = false;

        for (uint i = 0; i < lp_providers.length; i++) {
            // current user already join
            if (lp_providers[i] == msg.sender)
                providerJoined = true;
            else {
                address cur_provider = lp_providers[i];
                lps[cur_provider] = lps[cur_provider] * prev_token_reserves / token_reserves; // decrease other users' share proportionally, avoid underflow
            }
        }

        if (!providerJoined) lp_providers.push(msg.sender);

    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    // @param exchange rate: represent the ratio of token_reserves / eth_reserves, which is usually greater than 1 
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate, uint rate_denominator)
        public 
        payable
    {
        uint token_amount = amountETH * token_reserves / eth_reserves;

        require((token_amount * share_denominator) <= (lps[msg.sender] * token_reserves), "Cannot remove more than your provided liquidity.");

        require(token_reserves * rate_denominator >= eth_reserves * min_exchange_rate, "Slippage exceeds min threshold.");
        require(token_reserves * rate_denominator <= eth_reserves * max_exchange_rate, "Slippage exceeds max threshold.");

        // ensure pool will not be depleted 
        require(token_reserves - token_amount > 0, "Cannot deplete token reserves to 0");
        require(eth_reserves - amountETH > 0, "Cannot deplete ETH reserves to 0");

        // send tokens and eth back to provider
        token.transfer(msg.sender, token_amount);
        payable(msg.sender).transfer(amountETH);

        // update states
        uint prev_token_reserves = token_reserves;
        token_reserves = token.balanceOf(address(this));
        eth_reserves = address(this).balance;
        k = token_reserves * eth_reserves;
        
        // update shares of liquidity providers
        lps[msg.sender] = (lps[msg.sender] * prev_token_reserves - token_amount * share_denominator) / token_reserves;

        uint senderIdx = 0;
        for (uint i = 0; i < lp_providers.length; i++) {
            if (lp_providers[i] == msg.sender) senderIdx = i;
            else {
                address cur_provider = lp_providers[i];
                lps[cur_provider] = lps[cur_provider] * prev_token_reserves / token_reserves; 
            }
        }

        // remove user from the array if she's share goes down to 0
        if (lps[msg.sender] == 0) removeLP(senderIdx);

    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    // @param exchange rate: represent the ratio of token_reserves / eth_reserves, which is usually greater than 1 
    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate, uint rate_denominator)
        external
        payable
    {
        uint eth_amount = lps[msg.sender] * eth_reserves / share_denominator;

        removeLiquidity(eth_amount, max_exchange_rate, min_exchange_rate, rate_denominator);

    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    // @param exchange rate: represent the ratio of token_reserves / eth_reserves, which is usually greater than 1 
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate, uint rate_denominator)
        external 
        payable
    {
        require(amountTokens > 0, "Amount of tokens to swap must be greater than 0.");

        require(amountTokens <= token.balanceOf(msg.sender), "Your token amount is not sufficient to swap.");

        require(token_reserves * rate_denominator <= eth_reserves * max_exchange_rate, "Slippage exceeds max threshold.");

        uint eth_amount = eth_reserves - (k / (token_reserves + amountTokens));
        // liquidity rewards
        uint eth_fee = eth_amount * swap_fee_numerator / swap_fee_denominator;
        eth_amount -= eth_fee;

        require(eth_reserves - eth_amount > 0, "Cannot deplete ETH reserves to 0");

        // perform swap
        token.transferFrom(msg.sender, address(this), amountTokens);
        payable(msg.sender).transfer(eth_amount);

        // update states
        token_reserves = token.balanceOf(address(this));
        eth_reserves = address(this).balance;
        
    }



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    // @param exchange rate: represent the ratio of token_reserves / eth_reserves, which is usually greater than 1 
    function swapETHForTokens(uint max_exchange_rate, uint rate_denominator)
        external
        payable 
    {
        require(msg.value > 0, "Amount of eth to swap must be greater than 0.");

        require(token_reserves * rate_denominator <= eth_reserves * max_exchange_rate, "Slippage exceeds max threshold.");

        uint token_amount = token_reserves - (k / (eth_reserves + msg.value));
        uint token_fee = token_amount * swap_fee_numerator / swap_fee_denominator;
        token_amount -= token_fee;

        require(token_reserves - token_amount > 0, "Cannot deplete token reserves to 0");

        // perform swap
        token.transfer(msg.sender, token_amount);
        
        // update states
        eth_reserves = address(this).balance;
        token_reserves = token.balanceOf(address(this));

    }
}
