// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

 
// Token contract
contract Token is Ownable, ERC20 {
    string private constant _symbol = 'RYDT';
    string private constant _name = 'Ryan DEX Token'; 

    constructor() ERC20(_name, _symbol) {}

    bool private mintingAllow = true;

    // Function _mint: Create more of your tokens.
    // You can change the inputs, or the scope of your function, as needed.
    // Do not remove the AdminOnly modifier!
    // @param amount: amount of token in SMALLEST DIVISIBLE unit 
    function mint(uint amount) 
        public 
        onlyOwner
    {
        require(mintingAllow, "Minting new token is disabled.");
        _mint(msg.sender, amount);
    }

    // Function _disable_mint: Disable future minting of your token.
    // You can change the inputs, or the scope of your function, as needed.
    // Do not remove the AdminOnly modifier!
    function disable_mint()
        public
        onlyOwner
    {
        mintingAllow = false;
    }
}