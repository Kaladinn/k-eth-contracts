// SPDX-License-Identifier: UNLICENSED


/**
 * Deploying with library.
 * Ideally, you don't want to insert all of the lib code into your contract deployment- then no gas savings! Instead, you need to tell compiler to look for a specific address
 * of an already compiled library so that compiler can insert this address into the bytecode.
 * In remix, you need to go into contracts/artifacts, then change the .json file to autoDeployLib to false, and copy and paste in the address. Good article on this: https://medium.com/remix-ide/deploying-with-libraries-on-remix-ide-24f5f7423b60.
 * If using solc, then you can just use the --link and --libraries flags. Good article: https://ethereum.stackexchange.com/questions/6927/what-are-the-steps-to-compile-and-deploy-a-library-in-solidity

 * You also need to make sure that the .deps file is pointing to the correct github thing. Remix will save your deps, and if you update the github, wont repull, so you
 * have to go in, delete the .deps, then recompile. https://remix-ide.readthedocs.io/en/latest/import.html

 * Finally, you need to go through and take every instance of __$......$__ and replace it with the exact address (NO 0x prepended) in the bytecode.
*/

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/Kaladinn/stormLibrary/blob/main/StormLibrary.sol";


contract Storm {
    address immutable public owner; //public so people can ensure that contract owner is signing of chain msgs correctly for a given contract(node code)
    mapping(address => uint) public tokenAmounts; //mapping from token to amount. 
    uint248 public lockCount; //num ongoing swaps
    uint8 reentrancyLock; //usually 0, but if enter function that makes external calls, then is set to 1(then back to 0 at end). All external non-view facing functions check that when entered, reentrancyLock == 0. 
    
    mapping(uint => StormLib.Channel) channels; //TO DO: do we want this to be public?
    mapping(uint => StormLib.SwapStruct) public seenSwaps;
    
    constructor () payable {
        owner = msg.sender;
        tokenAmounts[address(0)] = msg.value;
    }

    //****************************** Debugging Methods *****************************/

    function getContractBalances(address[] calldata tokens) external view returns (bytes memory) {
       return StormLib.getContractBalances(tokens, tokenAmounts);
    }
    


    //****************************** Debugging Methods *****************************/


    /** TO DO: we could delete this, and it would save us up to 0.01 ETH. Can always do this using addFundsToContract
     * Fallback. Call if want to stake more ETH into the contract. 
     */
    receive() external payable {
        require(reentrancyLock == 0, "a");
        tokenAmounts[address(0)] += msg.value;
    }


    //function that will revert if not eligble for withdraw. Called by both clients to know if able to withdraw, and internally by the withdraw function. 
    function eligibleForWithdraw(bytes calldata message, uint channelID, uint numTokens) public view {
        StormLib.eligibleForWithdraw(message, channels[channelID], numTokens);
    }

    
    //Pulls funds from the other contract
    function addFundsToContract(address[] calldata tokens, uint[] calldata funds) external payable {
        require(reentrancyLock == 0, "a");
        require(msg.sender == owner, "g");
        for (uint i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            bool success = token.transferFrom(owner, address(this), funds[i]); 
            tokenAmounts[tokens[i]] += funds[i];
        }
        tokenAmounts[address(0)] += msg.value;
        //TO DO: emit event here detailing all tokens added?. 
    }


    /**
     * Called when the owner wants to delete the smart contract. Sends funds to owner. Note that any IERC20s
     * that have approved this contract to spend from an allowance will need to be set back to 0 independently of terminateContract.
     */
    function terminateContract(IERC20[] calldata tokensInContract) external {
        require(reentrancyLock == 0, "a");
        reentrancyLock = 1;
        require(msg.sender == owner && lockCount == 0, "h"); 
        for (uint i = 0; i < tokensInContract.length; i++) {
            tokensInContract[i].transfer(owner, tokenAmounts[address(tokensInContract[i])]); 
            // delete tokenAmounts[address(tokensInContract[i])];         //TO DO: is it more cheap/get a gas refund to delete all of the metadata? Or is this done automatically since its a self destruct? If not, delete this and below line. 
        }
        // reentrancyLock = 0;
        selfdestruct(payable(owner));
    }

    
    //NOTE: in multichain, chain on which secret holder is receiving funds must have both a shorter timeout anddd a shorter deadline, where intrachain deadline must also be shorter than timeout.
        //the reason for this is that we don't want secretholder to delay publishing msg on chain where they are receiving to last second, then publish and leave other chains deadline expired, essentially stealing funds.
        //furthermore, lets say both are pubbed at same time, we want the redeem period to be shorter on the receiving chain, so nonsecretholder always has time to redeem on their chain. Finally, we need that the timeout is always longer than
        //the deadline for a chain, so that we cant have a msg pubbed, redeemed, and then erased, and then published again since the deadline hasn't passed. This is partial as is because we store the timeout in the struct that is stored in seenMsgs,
        //and this struct cant be deleted till timeout has expired
    //NOTE: if reverted, then entryToDeleteOrPreimage should be zero, to save calldata costs and also emit event costs. 
    function singleswap(bytes calldata message, bytes calldata signatures, uint entryToDeleteOrPreimage) external payable {
        require(reentrancyLock == 0, "a");
        reentrancyLock = 1;

        if (signatures.length != 0) {
            //signatures.length is our simple way of indicating that this is a singleswapRedeem. Could separate into two functions, but we save gas this way w only 1 func. Too bad sol. doesn't support optional params
            //this is singleswapStake. entryToDeleteOrPreimage acting as entryToDelete
            uint swapID = StormLib.singleswapStake(message, signatures, entryToDeleteOrPreimage, owner, tokenAmounts, seenSwaps);
            emit StormLib.Swapped(swapID);
        } else {
            //entryToDeleteOrPreimage operating as preimage now
            (uint swapID, bool redeemed) = StormLib.singleswapRedeem(message, entryToDeleteOrPreimage, tokenAmounts, seenSwaps);
            emit StormLib.MultichainRedeemed(swapID, redeemed, entryToDeleteOrPreimage); 
        }
        lockCount += 1;
        reentrancyLock = 0;
    }


    //Fns that take in balanceTotalsHash unhashed string balanceTotals:
        //update
        //addFundsToChannel
        //settle
        //settleSubset
        //startDispute
    //NOTE: The uint[] balanceTotals is tacked onto the end of message. We do this to avoid issues with call stack too deep errors.
    function channelGateway(bytes calldata message, bytes calldata signatures, StormLib.ChannelFunctionTypes channelFunction) external payable {
        require(reentrancyLock == 0, "a");
        //lock and contract that calls out to IERC20, which are all but update and startdispute
        if (channelFunction != StormLib.ChannelFunctionTypes.UPDATE && channelFunction != StormLib.ChannelFunctionTypes.STARTDISPUTE) { reentrancyLock = 1; }

        if (channelFunction == StormLib.ChannelFunctionTypes.ANCHOR) {
            uint channelID = StormLib.anchor(message, signatures, owner, channels, tokenAmounts);
            lockCount += 1;
            emit StormLib.Anchored(channelID, message[StormLib.START_ADDRS : (message.length - 32)]);
        } else if (channelFunction == StormLib.ChannelFunctionTypes.UPDATE) {
            StormLib.update(message, signatures, owner, channels);
        } else if (channelFunction == StormLib.ChannelFunctionTypes.ADDFUNDSTOCHANNEL) {
            (uint channelID, uint32 nonce) = StormLib.addFundsToChannel(message, signatures, owner, channels, tokenAmounts);
            emit StormLib.FundsAddedToChannel(channelID, nonce, message[StormLib.START_ADDRS: message.length]);
        } else if (channelFunction == StormLib.ChannelFunctionTypes.SETTLE) {
            uint channelID = StormLib.settle(message, signatures, owner, channels, tokenAmounts);
            lockCount -= 1;
            emit StormLib.Settled(channelID, message[StormLib.START_ADDRS: message.length]);
        } else if (channelFunction == StormLib.ChannelFunctionTypes.SETTLESUBSET) {
            (uint channelID, uint32 nonce) = StormLib.settleSubset(message, signatures, owner, channels, tokenAmounts);
            emit StormLib.SettledSubset(channelID, nonce, message);
        } else if (channelFunction == StormLib.ChannelFunctionTypes.STARTDISPUTE) {
            (uint channelID, uint32 nonce, StormLib.MsgType msgType) = StormLib.startDispute(message, signatures, owner, channels);
            emit StormLib.DisputeStarted(channelID, nonce, msgType);
        } else if (channelFunction == StormLib.ChannelFunctionTypes.WITHDRAW) {
            (uint channelID, uint numTokens) = StormLib.withdraw(message, channels, tokenAmounts);
            lockCount -= 1;
            emit StormLib.Settled(channelID, message[StormLib.START_ADDRS : StormLib.START_ADDRS + (numTokens * StormLib.TOKEN_PLUS_BALS_UNIT)]);
        } else { revert('D'); }

        //unlock and contract that calls out to IERC20, which are all but update and startdispute
        if (channelFunction != StormLib.ChannelFunctionTypes.UPDATE && channelFunction != StormLib.ChannelFunctionTypes.STARTDISPUTE) { reentrancyLock = 0; }
    }



    /**
     * Done to push either push fwd(normal, turing incomplete), or revert(turing incomplete) a shard. 
     * For this call to succeed, there must be a settlement on a Sharded message already in place.
     * Must still call withdraw when timeout ends. Balances are set here, but funds not yet distributed. 
     */
    function changeShardState(bytes calldata channelIDMsg, uint hashlockPreimage, uint8[] calldata shardNos) external {
        require(reentrancyLock == 0, "a");
        (uint channelID, uint msgHash) = StormLib.changeShardState(channelIDMsg, hashlockPreimage, shardNos, channels);
        emit StormLib.ShardStateChanged(channelID, shardNos, hashlockPreimage, msgHash);
    }

}


