// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";


// channelID:
//     uint8 disputeBlockTimeout
//         single byte because the value represents the number of hours of the timeout in blocks. i.e. for eith, disputeBlockTimeout = 1 corresponds to 240 blocks.
//         This is the timeout, a constant in the channel, that last from when startDispute is called, in blocks. 
//         Other parties can trump this message as long as it falls within disputeBlockTimeout. 
//         Note that even after disputeBlockTimeout has ended, parties can still change shardBlockTimeouts. Also, a withdraw call cant succed until after this timeout has ended, to allow counterparty time to trump. 
//     uint32 contractNonce:
//         this is the nonce for the channel, which is incremented for every new channel that is entered into in the contract. 
//         This is to prevent against a replay attack by someone who has restaked into the contract with the same tokens,
//         otherTokens, and also the same address. Also, this needs to be kept track of in an off chain DB, for if this were an on chain variable, it would a). be more expensive. 
//         b). could allow a party to resubmit an anchor multiple times, as the anchor would get the contractNonce added on chain, have a differnet channelID, 
//         and would not be recognized as a repeat.
//     uint24 chainID 
//         (use to differentiate between two blockchains that may have naming overlap, so that is anchored into intended chain). I anticipate 2^24 is a high enough value to capture any chain we may need.
//     address partnerAddr
//         the address of the person providing funds. This is where funds are received from, and sent to. This sig is only checked in anchor and singleswapStake
//     address contractAddress
//     address pSignerAddr
//         the address that the partner person uses to sign messages. This may be the same as partnerAddr.
//     byte numTokens
//         represents number of 20 byte ERC20 addrs below that are in contract. Note this is limited to 255 by nature of being a byte. 
//     address[] tokens:
//         array of ERC. If first addr = 0x000000..0000 (20 bytes of 0), then represents ether. All other addresses assumed to be ERC20. 

// shardDataMsg: 
    // uint8[] shardStates
        //stores all of the states of 0, 1, 2, 3 for each shards state (INITIAL, REVERTED, PUSHEDFORWARD, SLASHED)
            //indicates whether hashlock owner revealed the secret, and pushed state forward. Now, we have this in an interesting way as a uint8.
                //MOTIVATION: create a solution where we dont require Alice to stay live and publish herself in the last hour of the timeout, but don't give Bob/watchtower colluding with Bob any ability to hurt Alice.
                
                //0 indicates that it is in its base state, which is to revert. (TO DO: make base form to push forward? test to see which is more common, then choose one that causes fewest on chain changeShardState calls)
                //1 (INCLUDESTURINGINCOMPLETE only) indicates that it is in the revert state from a reveal of secret to revertHashlock
                //2  indicates that it is in the fwd state from a reveal of secret to forwardHashlock
                //3  indicates that whoever owns hashlock has cheated in some way. 
                    
                    //If INCLUDESTURINGINCOMPLETE:
                    // Cheating determined by revealing two secrets. So, if fwd secret pubbed in (1), or revert secret in (2),
                    //then we enter (3). This allows watchtower aid so that we don't require only Alice having publishing power to Ethereum in last hour; Bob can publish too, but if he does one thing on BTC, another on ETH, or tries to flip on ETH right at end of timeout, Alice or watchtower
                    //can publish BTC revealed secret/he will end up slashing himself. (Note that order of Bob and Alice/Watchtower pub here is unimportant).
                        //bug concern: Bob pubs to ETH, does nothing on BTC. Alice must publish tx_delay on BTC before Ethereum expires. Else, Bob could race case her after ETH times out in revert state and publish tx2F. However
                            //if she pubs tx_delay, Bob can push forward ETH, and Alice can do nothing about moving BTC forward as well.
                                //SOLUTION: we have tx_delay have three things in Bobs ScriptPK. Can be redeemed as follows. First t = 0, Bob sig + cc Alice. Second t = 1, Alice sig + secretForwardBob. Third t = 2, Bob sig. NOTE: Alice ScriptPK in this txdelay is a standard lightning ScriptPK: Bob redeem instant w cc, Alice redeem at timeout t. 
                                    //Now, the timeouts functions so that Bob will have enough time to figure out fwd or rvrt with upstream. Then, he SHOULD publish txR, txF. This is all before tx1d becomes valid. Now, with at least 1 hr left on eth,
                                    //tx1d becomes valid. Alice publishes this. Finally, ample enough time before t = 2, the eth contracts times out. This means if Bob pushes forward eth at last second, Alice will still have ability to slash and steal Bobs BTC funds.
                                    //Finally, in case where Alice has a downstream, this eth timeout happens before her downstream is able to publish her own tx1d. Note that this is not protected by watchtowers, as she cant send both tx2f, tx2r to watchtowers without placing too much trust in them. 
                                        //However, note that Alice will only have a upstream/downstream if she is routing swaps, which means she would be running a full node anyways, so there is no (minimal?) problem here.
                                    //WATCHTOWERS: Alice is assumed to be fully offline. She publishes ETH2 on her own, and advertises to watchtowers the associated bitcoin pk. She also sends the watchtowers
                                    //tx1delay, to publish when becomes valid if Bob has not published on BTC, as well as a signature to spend from Bob's output of the txdelay1 ScriptPK. Then, she falls offline! Trusts watchtowers to pub BTC, slash Bobs BTC if necessary, and transfer published BTC secrets
                                    //to chain on ETH, and if Bob double reveals, to slash him on ETH. 
                                        //TO DO: I believe that in order for Alice to send a proper sig spending from Bobs tx1delay scriptPK, it will need to be (coming from?, going to?
                            
                        //Q: whats stopping watchtowers from publishing any of the old msgs which have now had their CC revealed? Answer: you only send watchtower signed msg if you want that one to go to chain. Else, you just send over all cancel codes.

                    //If not INCLUDESTURINGINCOMPLETE:
                        //Originally, only the non secret owning party were able to publish in the last hour, with 2 hour timeout chunks. Imagine you go to chain with both your upstream, timeout 2 hours, and downstream, timeout 4. Your upstream has 1 hour to publish. Then, you have another hour to see this, 
                        //publish to the appropriate chains. That leaves two hours left on your downstream, where you then have another hour to publish yourself. Finally, there is another hour for your downstream partner to publish.
                        
                        //I am proposing a new system. First, I propose a delay of 2 hours, 3 hours, 4 hours, 5 hours... First Person A has 1 hour to pub. Then there are 1, 2, 3, 4... hours remaining in all contracts. Person B has 1 hour to trump upstream, 1 to publish downstream. Now, 0, 1, 2, 3 hours remaining. Person 
                        //C has 1 hour to trump upstream, 1 to pub downstream. Now 0, 0, 1, 2 left. Person D has 1 hour to trump, 1 to pub. Finally, 0, 0, 0, 1. Person E has 1 hour to trump. 
                        
                        //In the previous system we were requiring that only the non owning party be able to publish their funds in the last hour. This meant that if the secret owning party waited till 1 hour, 1 second left in shard and published,
                        //no watchtower could see this in time and aid the non owning party. It required liveness on the non owning parties part to counteract the event of a last second pub. This is untenable for non node runners.
                        //Instead, I propose this new system: up until the final hour, anyone can publish. Then, during the final hour, anyone can publish, BUT if a secret is published FOR THE FIRST TIME, the secret owning party has all of their funds slashed. 
                        //So, secret owners can wait till last second on one chain, then publish, but this wont force state n + 1 on this chain, n on other chain. Instead, it pushes through ALL, n on the two chains. This is an acceptable state for the non owning party, and can only be brought about by malevolence by the owning party.
                        //Furthermore, it encourages secret owners to publish to all chains, and to do so very early. If they wait until the last second on one chain with 1 hour 1 second left, good chance on the other chain the update wont get pubbed in time, and they will be slashed.
                        // In the event that they go offline accidentally after a single chain pub, we are relying on our network of watchtowers to propagate this secret around well before the 1 hour left mark is hit. 
                        //Flaws: 
                            //could theoretically DoS both a user and all honest watchtowers to prevent pubs? Or concentrated effort on part of miners to censor txs so that a party gets slashed? But highly unlikely.
                            //If a blockchain goes down, like Solana earlier this year, could cause some wonky issues, there to be timeout discrepancies between the chains. IDK how to get around this issue. 
                            //If we are going of unix timestamp, and times given by miners suuuuper whack, could be an issue. May be smart to keep the 2, 4, 6, etc. system as before in light of this. Furthermore, if we are using a 
                            //block based timestamp, and block times not predictable/ too fast (think first few weeks of BCH), could also present an issue. 
    // uint blockNumberAtDisputeStart
        //block # when dispute called, used in reference to determine when a shard times out, while storing mininal data

// msgHash:
    // keccak256(
        // Passed in msg with trailing nonce removed (deadline removed if is initial msg)
        // shardDataMsg (ONLY IF MSGTYPE == SHARDED)
    // )
    
// balanceTotalsMsg:
    //uint[] balances
        //just an array of uints for the total amount in each token (sum of owner, partner amounts)

// balanceTotalsHash:
    //uint160(keccak256(balanceTotalsMsg))


//shardData: (static 67)
    //uint8 tokenIndex.  
        //Index of the token being traded on. 
    //uint8 ownerGivingOrReceiving: 0: ownerReceiving. 1: ownerGiving
        //says whether owner is giving token to partner, or whether owner receiving it from partner
    //uint amount 
        // amount being traded on
    //uint8 shardBlockTimeoutHours
        //again, as other timeout, represents hours. 
    //uint hashlock



// msgType:
//     0: Initial
//     1: Unconditional
//     2: Sharded
//     3: Settle
//     4: SettleSubset
//     5: UnconditionalSubset
//     6: AddFundsToChannel
//     7: SingleChain
//     8: Multichain

// channelFunctionType:
//     0: ANCHOR
//     1: UPDATE
//     2: ADDFUNDSTOCHANNEL
//     3: SETTLE
//     4: SETTLESUBSET
//     5: STARTDISPUTE
//     6: WITHDRAW

// shardState:
//     0: INITIAL
//     1: REVERTED
//     2: PUSHEDFORWARD
//     3: SLASHED


// Messages:
//     Initial
//         byte msgType
//         (variable) channelID 
//         uint[] balances
//             array of all the balances, given by ownerAmount, then partnerAmount. 
//             For example, if there are two tokens in the channel, this will be 2 * (2 * 32) = 128 bytes long, arranged by ownerAmount0, partnerAmount0, ownerAmount1, partnerAmount1.
//             It is assumed balances in same order as tokens. Not side by side, bc balances change and channelID must be immutable. 
//         uint deadline
//             the block number by which this tx must be submitted. Used to scope validity of anchor signatures 
//     Unconditional
//         byte msgType
//         (variable) channelID 
//         uint[] balances
//         uint32 nonce
//     Sharded
//         byte msgType
//         (variable) channelID
//         uint[] balances
//         byte numShards
//             represents how many shards are attached to this Shard Msg
//         shardData[] shards
//             array of all the shards in the Shard msg
//         uint32 nonce
//     Settle
//         byte msgType
//         (variable) channelID 
//         uint[] balances (length: numTokens * 2 * 32)
//     SettleSubset
//         byte msgType
//         (variable) channelID 
//         uint[] balances
//         bool[] closeOutTokens
//         uint32 nonce
//     UnconditionalSubset
//         This message is exactly the same as an Unconditional except it requires that the on chain stored nonce == msg nonce - 1.
//         This is done to ensure that one party cannot publish the new tx, with a portion of the funds missing (bc presumedly settled) b4 a party can actually submit the settleSubset msg.
//     AddFundsToChannel
//         byte msgType
//         (variable) channelID 
//         uint[] fundsToAdd
//         nonce 
//     SingleChain
//         byte msgType
//         5 bytes zeros (padding) //done so that complies with anchor format, doAnchorChecks can be reused on this
//         uint24 chainID
//         address partnerAddr
//         address contractAddress
//         address ownerToken
//         address partnerToken
//         uint ownerAmount
//         uint partnerAmount
//         uint deadline
//     MultiChain
//         byte msgType
//         3 bytes zeros (padding) //done so that complies with anchor format, doAnchorChecks can be reused on this
//         bool owner/partnerFlag. 00 if owner is providing the funds, 01 if partner providing
//         uint8 blockHourTimeout
//         uint24 chainID
//         address partnerAddr
//         address contractAddress
//         address personToken
//         uint personAmount
//         uint hashlock
//         uint deadline

//DESIGN DECISION: All timeouts that are checked in contract are valid up unitl that timeout occurs. For example, if the time is block 1000, then submission is valid at block 998, 999, 1000, but then invalud at 1001. 
    //Means you either check within deadline,timeout, valid if block.number <= timeout. For checking whether invalid, we make sure that block.number > timeout
    //for shardTimeout, final hour means less than 1 hour of blocks remaining. If exactly 1 hour remaining, does not count as a slashing case (the no TuringInComplete case)
    
library StormLib {
    event Anchored(uint indexed channelID, bytes tokensAndVals);
    event Settled(uint indexed channelID, bytes tokenBalances);
    event SettledSubset(uint indexed channelID, uint32 indexed nonce, bytes tokenBalances);
    event DisputeStarted(uint indexed channelID, uint32 indexed nonce, StormLib.MsgType indexed msgType); //TO DO: maybe delete msgType?
    event ShardStateChanged(uint indexed channelID, uint8[] indexed shardNos, uint preimage, uint msgHash);
    event FundsAddedToChannel(uint indexed channelID, uint32 indexed nonce, bytes tokensAdded);
    event Swapped(uint indexed msgHash); //in singlechain case, means that swap has completed. In multichain, means that has been anchored
    event MultichainRedeemed(uint indexed msgHash, bool redeemed, uint hashlock); //redeemed here is a variable that says whether the propoer preimage shown to unlcok funds. If false, means that timeout occurred and funds reverted back to their sources. if redeemed, hashlock is the proper preimage used.

    
    enum ChannelFunctionTypes { ANCHOR, UPDATE, ADDFUNDSTOCHANNEL, SETTLE, SETTLESUBSET, STARTDISPUTE, WITHDRAW }
    enum MsgType { INITIAL, UNCONDITIONAL, SHARDED, SETTLE, SETTLESUBSET, UNCONDITIONALSUBSET, ADDFUNDSTOCHANNEL, SINGLECHAIN, MULTICHAIN }
    enum ShardState { INITIAL, REVERTED, PUSHEDFORWARD, SLASHED } //BOTH TURING, NONTURING start in INITIAL. Have a distinction between initial and reverted for TURINGINCOMPLETE case, so know when secretOwner has revealed both push forward and revert.
    
    struct SwapStruct {
        uint hashlock;
        uint timeout;
    }

    struct BalancePair {
        uint ownerBalance;
        uint partnerBalance;
    }


    struct Channel {
        //slot 0
        bool exists; //Indicates that channel exists.
        bool settlementInProgress;
        uint32 nonce; 
        uint32 disputeBlockTimeout; //blockNumber before which a trump of the provided startSettlment message can be trumped w a higher nonce message. After this ends, can't start new settlement. However, before you can't withdraw. Important for notion of withdraw for non Sharded msgs.
        uint160 balanceTotalsHash; //hash of the total value locked into the contract for each token
        //slot 1
        uint msgHash; //Stores the keccak of the message used in startDispute. We do this so that we can check that in withdraw, this is the same msg as was used in startDispute. We need it bc we dont store all of balances in shard0, instead relying on the cheaper option of repassing them in calldata in withdraw.
    }


    uint constant BLOCKS_PER_HOUR = 240;
    
    //MAGIC NUMBERS
    uint8 constant NUM_TOKEN = 69;
    uint8 constant START_ADDRS = 70;
    uint8 constant TOKEN_PLUS_BALS_UNIT = 84;
    address constant NATIVE_TOKEN = address(0);
    uint constant LEN_SHARD = 67;
    

    //****************************** Debugging Methods *****************************/

    function getContractBalances(address[] calldata tokens,  mapping(address => uint) storage tokenAmounts) external view returns (bytes memory) {
        bytes memory balances = new bytes(tokens.length * 32);
        for (uint i = 0; i < tokens.length; i++) {
            address addr = tokens[i];
            uint val = tokenAmounts[addr];
            assembly{ mstore(add(add(balances, 32), mul(i, 32)), val) }
        }
        return balances;
    }
    

    //****************************** Debugging Methods *****************************/



    //function that will revert if not eligble for withdraw. Called by both clients to know if able to withdraw, and internally by the withdraw function. 
    function eligibleForWithdraw(bytes calldata message, Channel storage channel, uint numTokens) public view returns (uint8 numShards) {
        require(channel.exists && channel.settlementInProgress, "b");
        require(block.number > channel.disputeBlockTimeout, "c");

        uint shardPointer = START_ADDRS + (TOKEN_PLUS_BALS_UNIT * numTokens) + 1; //pointing to the first lenShard
        if (MsgType(uint8(message[0])) == MsgType.SHARDED) {
            numShards = uint8(message[shardPointer - 1]); //bc shardPointer pointing to first object after lenShard
        }
        
        //checks that all of the timeouts have occurred.
        uint shardSubmittedBlock;
        assembly { shardSubmittedBlock := calldataload(sub(add(message.offset, message.length), 32)) }
        for (uint8 i = 0; i < numShards; i++) {
            uint8 lenAmounts = 32 * uint8(message[shardPointer + 1 + numTokens]); //32 * numAmounts
            uint8 shardBlockTimeoutHours = uint8(message[shardPointer + 1 + numTokens + 1 + lenAmounts + 1]); //jump over lenShard, uint8[] oGOR, numAmounts, uint[] amounts, ownerControlsHashlock to arrive at shardBlockTimeoutHours
            ShardState shardState = ShardState(uint8(message[message.length - 32 - (numTokens - i)]));
            if (!(shardState == ShardState.SLASHED || (shardState == ShardState.PUSHEDFORWARD && uint8(message[shardPointer + 1 + numTokens + 1 + lenAmounts + 2]) == 0))) { //jump over lenShard, uint8[] oGOR, numAmounts, uint[] amounts, ownerControlsHashlock, shardBlockTimeoutHours to arrive at updateIncludesTuringIncomplete
                //if the shard is slashed, or the shard does not include turingIncomplete and is pushedForward, both of these states are irrevocable; nothing can be done to change them
                //so we automatically consider those shards timed out. Now, in this is statement, we check that these conditions ARENT true. This, we need to make sure that the shard has proeprly timed out
                require(block.number > shardSubmittedBlock + (shardBlockTimeoutHours * BLOCKS_PER_HOUR), "d");
            } 
            shardPointer += 32 * uint8(message[shardPointer]); //jump ahead to next shard, doing 32 * lenShard
        }
    }

    

    /**
     * checks that given a message and two pairs of signatures, the signatures are valid for the keccak of the message,
     * given that ownerSignature matches owner of the contract, and partnerSignature matches partnerAaddress that is embedded in message as part of pairID.
     * Signatures are ECDSA sigs in the form v || r || s. Also, signatures in form ownerSignature | partnerSignature.
     * Is anchor states whether we should use partnerAddr(anchoring), or pSignerAddr(everything else)
     */
    function checkSignatures(bytes calldata message, bytes calldata signatures, address owner, address nonOwnerAddr) private pure {
        bytes32 messageHash = keccak256(message);
        bytes32 r;
        bytes32 s;
        assembly {
            r := calldataload(add(signatures.offset, 0))
            s := calldataload(add(signatures.offset, 32))
        }
        uint8 magicETHNumber = 27; //27 is magic eth # to add to v value, per ETH docs
        require(address(ecrecover(messageHash, magicETHNumber + uint8(signatures[64]), r, s)) == owner, "n");

        assembly {
            r := calldataload(add(signatures.offset, 65))
            s := calldataload(add(signatures.offset, 97))
        }
        require(address(ecrecover(messageHash, magicETHNumber + uint8(signatures[129]), r, s)) == nonOwnerAddr, "o"); 
    }


    //checks that there is sufficient liquidity to add tokens, and then do so. 
    function lockTokens(bytes calldata tokens, uint numTokens, address partnerAddr, mapping(address => uint) storage tokenAmounts) private returns ( uint160 ) {
        uint _ownerBalance;
        uint _partnerBalance;
        address tokenAddress;
        uint[] memory balances = new uint[](numTokens);
        uint startBal = numTokens * 20;

        for (uint i = 0; i < numTokens; i++) {
            assembly { 
                tokenAddress := calldataload(add(sub(tokens.offset, 12), mul(i, 20))) //MAGICNUMBERNOTE: bc tokens starts at first tokenAddr, is 20 bytes, so we go back -12 so that -12+32 ends at 20
                _ownerBalance := calldataload(add(tokens.offset, add(startBal, mul(i, 64))))
                _partnerBalance := calldataload(add(tokens.offset, add(startBal, add(32, mul(i, 64)))))
            }
            balances[i] = _ownerBalance + _partnerBalance;
            if (i == 0 && tokenAddress == NATIVE_TOKEN) {
                //process ETH
                require(msg.value == _partnerBalance, "k");
            } else {
                IERC20 token = IERC20(tokenAddress);
                bool success = token.transferFrom(partnerAddr, address(this), _partnerBalance);
                require(success, "j");
            }
            tokenAmounts[tokenAddress] -= _ownerBalance; //solidity 0.8.x should catch overflow here. 
        }
        //have looped through all of them, update the balances in the tokenAmounts, and also encountered no errors! can now set balances to be balances in this msg.
        return uint160(bytes20(keccak256(abi.encodePacked(balances))));
    }


    function doAnchorChecks(bytes calldata message) private view returns (uint) {
        uint assemblyVariable; //first is chainID, then is contractAddress, then finally deadline
        assembly { assemblyVariable := calldataload(sub(message.offset, 23)) } //MAGICNUMBERNOTE: bc chainID sits at position 6-8, so -23 + 32 = 9, will have last byte as pos. 8, as desired!
        require(uint(uint24(assemblyVariable)) == block.chainid, "q"); //have to cast it to a uint24 bc thats how it is in message, to strip out all invalid data before it, then recast it to compare it to the chainid, which is a uint. 

        assembly { assemblyVariable := calldataload(add(message.offset, 17)) } //MAGICNUMBERNOTE: bc contractAddress ends at NUM_TOKEN (or 49), so we do NUM_TOKEN - 32 = 17 
        require(address(uint160(assemblyVariable)) == address(this), "r");

        assembly{ assemblyVariable := calldataload(add(message.offset, sub(message.length, 32))) } //MAGICNUMBERNOTE: -32 from end bc deadline uint, at very end msg
        require(block.number <= assemblyVariable, "t");
        return assemblyVariable;
    }

    //Goes through, and transfer into the contract the necessary funds
    function processFundsSingleswap(bytes calldata message, uint8 person, bool singleChain, address partnerAddr, mapping(address => uint) storage tokenAmounts) private {
        //process funds
        uint ownerAmount;
        uint partnerAmount;
        address addr;
        assembly { 
            addr := calldataload(add(message.offset, 37))//MAGICNUMBERNOTE: fetching ownerToken, which sits at 37 + 32 = 69
            ownerAmount := calldataload(add(message.offset, 89))//MAGICNUMBERNOTE: fetching ownerAmount, which starts at 89, uint
        }
        if (person == 0 || singleChain) {
            //these are funds owner is providing
            tokenAmounts[addr] -= ownerAmount;
            if (singleChain) {
                //distribute funds instantly
                if (addr == NATIVE_TOKEN) {
                    //is native token
                    payable(partnerAddr).transfer(ownerAmount);
                } else {
                    bool success = IERC20(addr).transfer(partnerAddr, ownerAmount);
                    require(success, "j");
                }
            }
        } else if (person == 1 || singleChain) {
            //these are funds partner is providing
            if (singleChain) {
                //get new funds amount to reflect the partner funds
                assembly {
                    addr := calldataload(add(message.offset, 57))//MAGICNUMBERNOTE: fetching partnerToken, which sits at 57 + 32 = 89
                    partnerAmount := calldataload(add(message.offset, 121))//MAGICNUMBERNOTE: fetching partnerAmount, which starts at 121, uint
                }
                tokenAmounts[addr] += partnerAmount;
            }
            if (addr == NATIVE_TOKEN) {
                require(msg.value == partnerAmount, "k");
            } else {
                bool success = IERC20(addr).transferFrom(partnerAddr, address(this), partnerAmount);
                require(success, "j");
            }
        }
    }
    
    //NOTE: in multichain, chain on which secret holder is receiving funds must have both a shorter timeout than other chain. 
        //the reason for this is that we don't want secretholder to delay redeeming msg on chain where they are receiving to last second, then not leave nonsecretholder enough time to redeem on ther own chain. 
        //Secondly, we need that the timeout is always longer than the deadline for a chain, so that we cant have a msg pubbed, redeemed, and then erased, and then published again since the deadline hasn't passed.
    function singleswapStake(bytes calldata message, bytes calldata signatures, uint entryToDelete, address owner, mapping(address => uint) storage tokenAmounts, mapping(uint => SwapStruct) storage seenSwaps) external returns(uint swapID) {
        uint deadline = doAnchorChecks(message);
        address partnerAddr;
        assembly { partnerAddr := calldataload(sub(message.offset, 3)) } //MAGICNUMBERNOTE: sits at finish at 29, and 29 - 32 = -3
        checkSignatures(message, signatures, owner, partnerAddr);
        swapID = uint(keccak256(message));
        require(seenSwaps[swapID].timeout == 0, "C");

        bool singleChain = false;
        uint8 person;
        uint8 timeoutHours;
        if (MsgType(uint8(message[0])) == MsgType.SINGLECHAIN) {
            singleChain = true;
        } else {
            require(MsgType(uint8(message[0])) == MsgType.MULTICHAIN, "G");
            person = uint8(message[4]);
            timeoutHours = uint8(message[5]);
        }
        processFundsSingleswap(message, person, singleChain, partnerAddr, tokenAmounts);
        if (singleChain) {
            seenSwaps[swapID].timeout = deadline;
        } else {
            uint hashlock;
            assembly{ hashlock := calldataload(sub(message.length, 64)) }
            seenSwaps[swapID].hashlock = hashlock;
            seenSwaps[swapID].timeout = block.number + (timeoutHours * BLOCKS_PER_HOUR);
        }

        //gas saver, clears out old entries to make putting in our entry above less costly. First checks that deadline has expired, so that can't do replay attack. 
        if (block.number > seenSwaps[entryToDelete].timeout && seenSwaps[entryToDelete].hashlock == 0) {
            delete seenSwaps[entryToDelete];
        }
        
    }

    //only available/necessary if singleSwap is multichain
    function singleswapRedeem(bytes calldata message, uint preimage, mapping(address => uint) storage tokenAmounts, mapping(uint => SwapStruct) storage seenSwaps) external returns(uint swapID, bool redeemed) {
        swapID = uint(keccak256(message));
        require(seenSwaps[swapID].hashlock != 0, "D"); //funds have already been redeemed, or wasn't a multichain in the first place!
        //valid redemption, should now send the proper funds to the proper person
        
        uint8 person = uint8(message[4]);
        //process funds
        address partnerAddr;
        uint amount;
        address addr;
        assembly { 
            partnerAddr := calldataload(sub(message.offset, 3))
            addr := calldataload(add(message.offset, 37))//MAGICNUMBERNOTE: fetching personToken, which sits at 37 + 32 = 69
            amount := calldataload(add(message.offset, 89))//MAGICNUMBERNOTE: fetching personToken, which starts at 89, uint
        }
        
        bool timedOut = block.number > seenSwaps[swapID].timeout;
        if (timedOut) {
            //has timed out, which means we want to return the funds to sender. This is the exact same code, but with values flipped. To avoid code duplication, 
            //we can instead just flip the person, so the funds return to owner/partner instead of partner/owner.
            person = (person == 0) ? 1 : 0;
        } else {
            //hasn't timed out yet
            require(seenSwaps[swapID].hashlock == uint(keccak256(abi.encodePacked(preimage))), "E");
        }
        if (person == 0) {
            //is owner, so owner paid, means partner should receive. OR, got flipped up above, so is owner, but partner paid, which means partner gets return
            if (addr == NATIVE_TOKEN) {
                payable(partnerAddr).transfer(amount);
            } else {
                bool success = IERC20(addr).transfer(partnerAddr, amount);
                require(success, "j");
            }
        } else {
            //is partner, so partner paid, owner should receive. OR, got flipped up above, so is partner, but owner paid, owner gets return
            tokenAmounts[addr] += amount;
        }
        
        if (timedOut) {
            //now safe to fully delete
            delete seenSwaps[swapID];
        } else {
            //just delete hashlock, not whole structure bc deadline may not have yet timed out, we don't want a replay attack
            delete seenSwaps[swapID].hashlock;
        }
        redeemed = (!timedOut); //returns value for redeemed, which is 0 if timedOut, 1 if not timedOut, as desired
    }
    
    
    /**
     * Entry point for anchoring a pair transaction. If ETH is a token, anchor should be called 
     * by the partner, not the contract owner, since the partner must send value in through msg.value. This function only 
     * succeeds if the nonce is zero, deadline hasnt passed, and there is no open trading pair between these two people for 
     * the token pair. Only accepts an Initial message. 
     */
    function anchor(bytes calldata message, bytes calldata signatures, address owner, mapping(uint => Channel) storage channels, mapping(address => uint) storage tokenAmounts) external returns (uint) {
        doAnchorChecks(message);
        address partnerAddr;
        assembly { partnerAddr := calldataload(sub(message.offset, 3)) } //MAGICNUMBERNOTE: partnerAddr sits at finish at 29, and 29 - 32 = -3
        checkSignatures(message, signatures, owner, partnerAddr);
        require(MsgType(uint8(message[0])) == MsgType.INITIAL, "p");
    
        uint numTokens = uint(uint8(message[NUM_TOKEN])); //otherwise, when multiplying, will overflow
        
        uint channelID = uint(keccak256(message[1: START_ADDRS + (numTokens * 20)]));
        require(!channels[channelID].exists, "s");
        
        uint160 balanceTotalsHash = lockTokens(message[START_ADDRS : START_ADDRS + (TOKEN_PLUS_BALS_UNIT * numTokens)], numTokens, partnerAddr, tokenAmounts);
        Channel storage channel = channels[channelID];
        channel.exists = true;
        channel.balanceTotalsHash = balanceTotalsHash;
        return channelID;
    }


    /**
    * update() checks the current balances described in the passed message, then updates just the nonce. Update is called when you want to  
    * lock in a state to guarantee that you will never revert to a state before this. If you dont want to 
    * stay live but dont want to settle, you can call this with the most recent message and go offline for a period of time,
    * knowing startsettlment can not be called with a prior message, and no new messages will be signed, making you safe. 
    * We only update nonce so its cheaper, but do all the checks so a faulty signed msg couldn't permanently lock funds (no higher
    * nonced msgs, cant settle on this one, CP wont respond).
    * update() is only valid for Unconditional messages from an external call, for obvious reasons.
    * Not valid for a sharded Msg. Just call out to the watchtowers, sending them the double sig. TO DO: decide if want to make valid for shardedMsg
    */
    function update(bytes calldata message, bytes calldata signatures, address owner, mapping(uint => Channel) storage channels) external {        
        require (MsgType(uint8(message[0])) == MsgType.UNCONDITIONAL, "p");
        uint numTokens = uint(uint8(message[NUM_TOKEN]));
        address pSignerAddr;
        assembly { pSignerAddr := calldataload(add(message.offset, 37)) } //MAGICNUMBERNOTE: pSignerAddr sits at finish at 69, and 69 - 32 = 37
        checkSignatures(message[0: message.length - (32 * numTokens)], signatures, owner, pSignerAddr); //MAGICNUMBERNOTE: dont take whole msg bc the last 32*numTokens bytes are the balanceTotals string, not part of signature.
        uint channelID = uint(keccak256(message[1: START_ADDRS + (numTokens * 20)]));
        Channel storage channel = channels[channelID];
        require(channel.exists, "u");
        require(!channel.settlementInProgress, "w");//User should just call startDispute instead.
        
        require(channel.balanceTotalsHash == uint160(bytes20(keccak256(message[message.length - (32 * numTokens): message.length]))), "E"); //MAGICNUMBER NOTE: take last numTokens values, since these are the uint[] balanceTotals

        uint _ownerBalance;
        uint _partnerBalance;
        uint balanceTotal;
        for (uint8 i = 0; i < numTokens; i++){
            assembly {
                let startBals := add(add(message.offset, 70), mul(numTokens, 20)) //MAGICNUMBERNOTE: 70 for START_ADDRS
                _ownerBalance := calldataload(add(startBals, mul(i, 64)))
                _partnerBalance := calldataload(add(add(startBals, 32), mul(i, 64)))
                balanceTotal := calldataload(add(add(startBals, mul(numTokens, 64)), mul(i, 32))) //MAGICNUMBERNOTE: starts at end of balances (hence numTokens* 64)
            }
            require(_ownerBalance + _partnerBalance <= balanceTotal, "l");  //TO DO: should that be a strict equality?
        }
        
        //All looks good! Update nonce(the only thing we actually update)
        uint32 nonce;
        assembly { nonce := calldataload(add(message.offset, sub(message.length, add(32, mul(numTokens, 32))))) } //MAGICNUMBERNOTE: this comes from removing the balanceTotals, then skipping back 32 for the nonce
        channel.nonce = nonce;
    } 

    //loop over the tokens, and if the balance field is not 0, then we make the requisite calls
    function addFundsHelper(bytes calldata message, uint numTokens, mapping(address => uint) storage tokenAmounts) private returns (uint160 balanceTotalsHashNew) {
        address tokenAddress;
        uint amountToAddOwner;
        uint amountToAddPartner;
        uint prevBalanceTotal;
        address partnerAddr; //is calced here not in addFundsToChannel, bc msg sig was based off of pSignerAddr, whihc may not actually have possession of funds
        assembly { partnerAddr := calldataload(sub(message.offset, 3)) }//MAGICNUMBERNOTE: -3 bc ends at 29, 29 - 32 = -3

        uint[] memory balanceTotalsNew = new uint[](numTokens);
        for (uint8 i = 0; i < numTokens; i++) {
            assembly { 
                let startBalOwner := add(add(add(message.offset, 70), mul(20, numTokens)), mul(i, 64)) //MAGICNUMBERNOTE: 70 bc is start of addrs, and we add 20 * numTokens to this to get start of balances
                tokenAddress := calldataload(add(add(message.offset, 58), mul(i, 20)))//MAGICNUMBERNOTE: 58 bc 70 is start of addrs, but is only 20 bytes, not 32, so we go to 70 -12 = 58
                amountToAddOwner := calldataload(startBalOwner)
                amountToAddPartner := calldataload(add(startBalOwner, 32))
                prevBalanceTotal := calldataload(add(add(add(message.offset, 70), mul(numTokens, 84)), mul(i, 32))) //MAGICNUMBERNOTE: 70 for start_addrs. starts at end of balances (hence numTokens* 84)
            }
            //process any owner added funds
            if (amountToAddOwner != 0) {
                tokenAmounts[tokenAddress] -= amountToAddOwner;
            }

            //process any partner added funds
            if (i == 0 && tokenAddress == NATIVE_TOKEN && amountToAddPartner != 0) {
                //is ETH. Process appropriately
                require(msg.value == amountToAddPartner, "k"); 
            } else if (amountToAddPartner != 0) {
                IERC20 token = IERC20(tokenAddress);
                bool success = token.transferFrom(partnerAddr, address(this), amountToAddPartner);
                require(success, "j");
            }
            balanceTotalsNew[i] = prevBalanceTotal + amountToAddOwner + amountToAddPartner;
        }
        balanceTotalsHashNew = uint160(bytes20(keccak256(abi.encodePacked(balanceTotalsNew))));
    }

    //add extra owner and partner funds to a channel, provided it is not settling?
    //check both signatures
    //check that channel exists and is not settling. 
    //check the nonce; must be greater than nonce stored. For protocol, this nonce should be equal to the highest nonced msg seen thus far in the channel, so that can still arbitrate on other msg, but also locks in funds at this state.Furthermore, strict greater than prevents replay attack with addFunds calls.
    //For each of the funds given, if not zero, try to add them from the contract(owner), or make the requisite IERC20 calls.
    function addFundsToChannel(bytes calldata message, bytes calldata signatures, address owner, mapping(uint => Channel) storage channels, mapping(address => uint) storage tokenAmounts) external returns (uint channelID, uint32 nonce) {
        require (MsgType(uint8(message[0])) == MsgType.ADDFUNDSTOCHANNEL, "p");
        uint numTokens = uint(uint8(message[NUM_TOKEN]));
        address pSignerAddr;
        assembly { pSignerAddr := calldataload(add(message.offset, 37)) } //MAGICNUMBERNOTE: pSignerAddr sits at finish at 69, and 69 - 32 = 37
        checkSignatures(message[0: message.length - (32 * numTokens)], signatures, owner, pSignerAddr); //MAGICNUMBERNOTE: dont take whole msg bc the last 32*numTokens bytes are the balanceTotals string, not part of signature.
        channelID = uint(keccak256(message[1: START_ADDRS + (uint(uint8(message[NUM_TOKEN])) * 20)]));  
        Channel storage channel = channels[channelID];
        require(channel.exists, "u");
        require(!channel.settlementInProgress, "w");
        require(channel.balanceTotalsHash == uint160(bytes20(keccak256(message[message.length - (32 * numTokens): message.length]))), "E");  //MAGICNUMBER NOTE: take last numTokens values, since these are the uint[] balanceTotals      

        assembly { nonce := calldataload(add(message.offset, sub(message.length, add(32, mul(numTokens, 32))))) } //MAGICNUMBERNOTE: this comes from removing the balanceTotals, then skipping back 32 for the nonce
        require(nonce > channel.nonce, "x"); //TO DO: probably not necessary? Could only fail if partners not following protocol.
        
        channel.balanceTotalsHash = addFundsHelper(message, numTokens, tokenAmounts);
        //set nonce
        channel.nonce = nonce;
    }

    //helper that distributes the funds, used by settle and settlesubset
    function distributeSettleTokens(bytes calldata message, uint numTokens, mapping(address => uint) storage tokenAmounts, bool finalNotSubset) private returns (uint160) {
        uint _ownerBalance;
        uint _partnerBalance;
        address tokenAddress;
        address partnerAddr;
        assembly { partnerAddr := calldataload(sub(message.offset, 3)) }//MAGICNUMBERNOTE: -3 bc ends at 29, 29 - 32 = -3
        
        uint[] memory balanceTotalsNew = new uint[]((finalNotSubset ? 0 : numTokens)); //TO DO: make sure this costs no gas if in settle case
        for (uint8 i = 0; i < numTokens; i++) {
            uint balanceTotal;
            assembly { balanceTotal := calldataload(add(add(add(message.offset, 70), mul(numTokens, 84)), mul(i, 32))) } //MAGICNUMBERNOTE:70 for start_addrs. starts at end of balances (hence numTokens* 84)
            if (balanceTotal != 0 && (finalNotSubset || (uint8(message[START_ADDRS + (TOKEN_PLUS_BALS_UNIT * numTokens) + i]) == 1))) {
                //should settle this token. Either bc nonempty and settle, or nonempty and subsetSettle with flag set
                assembly {
                    let startBalOwner := add(add(add(message.offset, 70), mul(numTokens, 20)), mul(i, 64)) //MAGICNUMBERNOTE: 70 bc start addrs
                    tokenAddress := calldataload(add(add(message.offset, 58), mul(i, 20))) //MAGICNUMBERNOTE: bc START_ADDRS is at 70, so first addr ends at 90, 90 - 32 = 58
                    _ownerBalance := calldataload(startBalOwner)
                    _partnerBalance := calldataload(add(startBalOwner, 32))
                }
                require(balanceTotal >= _ownerBalance + _partnerBalance, "l"); //TO DO: should this be strict equality??
                if (i == 0 && tokenAddress == NATIVE_TOKEN) {
                    payable(partnerAddr).transfer(_partnerBalance);
                } else {
                    IERC20 token = IERC20(tokenAddress);
                    token.transfer(partnerAddr, _partnerBalance);
                }
                tokenAmounts[tokenAddress] += _ownerBalance;
                if (!finalNotSubset) {
                    //is subset, so we want to trck the new balanceTotals
                    balanceTotalsNew[i] = 0;
                }
            }  
            if (!finalNotSubset) {
                //is subset, be we aren't settling this token, so we just keep it the same as before
                balanceTotalsNew[i] == balanceTotal;
            }  
        }
        return uint160(bytes20(abi.encodePacked(balanceTotalsNew)));
    }

    //TO DO: if any cheaper, combine this and settleSubset into one function. Need to test if it inc/dec funds for publishing contract and also flows.
    //TO DO: I have eliminated checks that msg.sender == partnerAddr, ownerAddr. This allows watchtower called settle. Are we okay with this? Seems safe to me.
    /**
     * Requires a settle message. When two parties agree they want to settle out to chain, they can sign a settle message. This is 
     * the expected exit strategy for a channel. Because its agreed upon as the last message, it is safe to immediately distribute funds
     * without needing to wait for a settlement period. 
     */
    function settle(bytes calldata message, bytes calldata signatures, address owner, mapping(uint => Channel) storage channels, mapping(address => uint) storage tokenAmounts) external returns(uint channelID) {
        require (MsgType(uint8(message[0])) == MsgType.SETTLE, "p"); 

        uint numTokens = uint(uint8(message[NUM_TOKEN]));
        channelID = uint(keccak256(message[1: START_ADDRS + (numTokens * 20)]));
        address pSignerAddr;
        assembly { pSignerAddr := calldataload(add(message.offset, 37)) } //MAGICNUMBERNOTE: pSignerAddr sits at finish at 69, and 69 - 32 = 37
        checkSignatures(message[0: message.length - (32 * numTokens)], signatures, owner, pSignerAddr); //MAGICNUMBERNOTE: dont take whole msg bc the last 32*numTokens bytes are the balanceTotals string, not part of signature.
        
        require(channels[channelID].exists, "u");
        require(channels[channelID].balanceTotalsHash == uint160(bytes20(keccak256(message[message.length - (32 * numTokens): message.length]))), "E"); //MAGICNUMBER NOTE: take last numTokens values, since these are the uint[] balanceTotals
        
        distributeSettleTokens(message, numTokens, tokenAmounts, true);
        
        //clean up
        delete channels[channelID];
    }


    function settleSubset(bytes calldata message, bytes calldata signatures, address owner, mapping(uint => Channel) storage channels, mapping(address => uint) storage tokenAmounts) external returns(uint channelID, uint32 nonce) {
        require (MsgType(uint8(message[0])) == MsgType.SETTLESUBSET, "p");

        uint numTokens = uint(uint8(message[NUM_TOKEN]));
        channelID = uint(keccak256(message[1: START_ADDRS + (numTokens * 20)]));
        address pSignerAddr;
        assembly { pSignerAddr := calldataload(add(message.offset, 37)) } //MAGICNUMBERNOTE: pSignerAddr sits at finish at 69, and 69 - 32 = 37
        checkSignatures(message[0: message.length - (32 * numTokens)], signatures, owner, pSignerAddr); //MAGICNUMBERNOTE: dont take whole msg bc the last 32*numTokens bytes are the balanceTotals string, not part of signature.
        require(channels[channelID].exists, "u"); 
        require(channels[channelID].balanceTotalsHash == uint160(bytes20(keccak256(message[message.length - (32 * numTokens): message.length]))), "E"); //MAGICNUMBER NOTE: take last numTokens values, since these are the uint[] balanceTotals
        require(!channels[channelID].settlementInProgress, "w"); //Cant distribute if settling; don't know which direction to shove the shards.
        
        assembly { nonce := calldataload(add(message.offset, sub(message.length, add(32, mul(numTokens, 32))))) } //MAGICNUMBERNOTE: this comes from removing the balanceTotals, then skipping back 32 for the nonce
        require(nonce > channels[channelID].nonce, "x");

        channels[channelID].balanceTotalsHash = distributeSettleTokens(message, numTokens, tokenAmounts, false);
        channels[channelID].nonce = nonce; //Enables the UnconditionalSubset msg to now be spent
    }

     

    /** 
     */
    function updateShards(Channel storage channel, bytes calldata message, MsgType msgType, uint numTokens) private {
        //check that startDispute is valid. TO DO: check all of these operations, esp assembly, for overflow
        
        uint shardPointer = START_ADDRS + (TOKEN_PLUS_BALS_UNIT * numTokens); //points to byte for numShards
        uint8 numShards = (msgType == MsgType.SHARDED) ? uint8(message[shardPointer]) : 0; 

        shardPointer += 1; //point to first tokenIndex
        uint[] memory balanceTotalsWithShards = new uint[](numTokens);
        for (uint8 i = 0; i < numShards; i++) { 
            //looping over ownerGivingOrReceivingFirst in shard in shardData
            uint amount;
            assembly { amount := calldataload(add(message.offset, add(shardPointer, 2))) } //point this to the start of amount, which is 2 after tokenIndex
            balanceTotalsWithShards[uint8(message[shardPointer])] += amount;
            //looped over amounts in the shard, now lets increment the shardPointer to jump and point to the next shard
            shardPointer += LEN_SHARD; //use LEN_SHARD to jump ahead to next shards tokenIndex
        }
            
        
        //We have updated all of the shards. Now, we need to check whether for a given token, it will exceed the allotted balance in the channel.
        //we do this by looping over all the balances, adding how much the shards will add to these when settled, making sure no overflow when compared with the stored balanceTotals
        uint startBal = START_ADDRS + (numTokens * 20);
        uint nonceOrDeadline = (msgType == MsgType.INITIAL) ? 32 : 4; //if Inital, we strip off a 32 byte deadline; if UNCOND, SHARD, we strip off a 4 byte nonce. Also relevant for knowing where balanceTotals start
        for (uint8 i = 0; i < numTokens; i++) {
            uint balanceTotal;
            uint notInShards;
            assembly {
                let startOwnerBal := add(message.offset, add(startBal, mul(64, i)))
                notInShards := add(calldataload(startOwnerBal), calldataload(add(startOwnerBal, 32)))
                balanceTotal := calldataload(add(add(add(add(message.offset, startBal), mul(numTokens, 64)), nonceOrDeadline), mul(i, 32))) //starts at end of shardedMsg, right after nonce or deadline. We start at startBals, jump over all the bals, then add 32/4 to jump over the deadline/nonce.
            }
            balanceTotalsWithShards[i] += notInShards;
            require(balanceTotalsWithShards[i] <= balanceTotal, "l"); //TO DO: should this be strict equality?
        }

        //none of the shards(if sharded) + ownerPartnerBals overflowed, so we create our msg, and then keccak, store this in the contract
        if (msgType == MsgType.SHARDED) {
            bytes memory shardDataMsg = new bytes(numShards + 32); //MAGICNUMBERNOTE: we store byte(numShards) + uint8[numShards] + uint(blockAtDisputeStart)
            uint blockNumber = block.number;
            assembly { mstore(add(add(shardDataMsg, 32), numTokens), blockNumber) } //add in block.number afterupdateStatus' array
            channel.msgHash = uint(keccak256(abi.encodePacked(message[0: message.length - (numTokens * 32) - 4], shardDataMsg))); //TO DO: make sure this packs correctly to a msgHash type for sharded
        } else {
            channel.msgHash = uint(keccak256(message[0 : message.length - (numTokens * 32) - nonceOrDeadline])); //We need everything(channelID, token splits, msg data, except for the balanceTotals and the nonce)
        }
    }

    function disputeStartedChecks(Channel storage channel, bytes calldata message, bytes calldata signatures, uint numTokens, address owner) private returns (uint32 nonce, MsgType msgType) {
        msgType = MsgType(uint8(message[0]));
        address partnerAddr;
        if (msgType != MsgType.INITIAL) {
            //if is initial, we dont touch nonce, and leave it initialized to 0. Remember, INITIALS end in a deadline, not a nonce, since nonce is implicitly 0
            assembly { 
                nonce := calldataload(add(message.offset, sub(message.length, add(32, mul(numTokens, 32))))) //MAGICNUMBERNOTE: this comes from removing the balanceTotals, then skipping back 32 bytes so 4 bytes for the nonce at end
                partnerAddr := calldataload(add(message.offset, 37)) //MAGICNUMBERNOTE: bc end of pSignerAddr sits at 69, 69 - 32 = 37. Using partnerAddr name to save call stack space
            }
            checkSignatures(message[0: message.length - (32 * numTokens)], signatures, owner, partnerAddr); //MAGICNUMBERNOTE: dont take whole msg bc the last 32*numTokens bytes are the balanceTotals string, not part of signature.  
            assembly { partnerAddr := calldataload(sub(message.offset, 3)) } //MAGICNUMBERNOTE: getting partnerAddr set correctly for check below, where we require msg.sender == partnerAddr
 
        } else {
            //is initial, so we want to check sig off of the partnerAddr, not pSignerAddr
            assembly { partnerAddr := calldataload(sub(message.offset, 3)) }//MAGICNUMBERNOTE: bc end of partnerAddr sits at 29, 29 - 32 = -3
            checkSignatures(message[0: message.length - (32 * numTokens)], signatures, owner, partnerAddr); //MAGICNUMBERNOTE: dont take whole msg bc the last 32*numTokens bytes are the balanceTotals string, not part of signature.   
        }


         //if after a subset settle, ensure that subset settle has been published
        if (msgType == MsgType.UNCONDITIONALSUBSET) {
            require(nonce == channel.nonce + 1, "x");
            msgType = MsgType.UNCONDITIONAL;
        } //TO DO: can potentially delete this check and UNCONDITIONALSUBSET data type, bc these txs should fail in case settleSubset not yet published, since the balanceTotalsHash should not match. Will require balance checks to use strict equality though, no <=/>=
        
        require(msgType == MsgType.INITIAL || msgType == MsgType.UNCONDITIONAL || msgType == MsgType.SHARDED, "p");

        if (!channel.settlementInProgress) {
            require(msg.sender == partnerAddr || msg.sender == owner, "i");//Done so that watchtowers cant startDisputes. They can only trump already started settlements.
            require(nonce >= channel.nonce, "x"); //>= includes equals for case where starting settlement with a message that was used in a update() call already. Note shards cannot be used in update(), so shards will always be >. Didn't include this separately since checking >= is the same as checking >, for if not settling no way sharded nonce could have already been seen
            uint8 disputeBlockTimeoutHours;
            assembly{ disputeBlockTimeoutHours := calldataload(sub(message.offset, 30)) } //MAGICNUMBERNOTE: 30 bc disputeBlockTimeout sits at position 01, so -30 + 32 = 2, will have last byte as pos. 1, as desired!
            channel.disputeBlockTimeout = uint32(block.number + (uint(disputeBlockTimeoutHours) * BLOCKS_PER_HOUR)); //Note we only set this first startDispute call: all subsequent trumps must make it within this initially activated timeout. There is no reset.
            channel.settlementInProgress = true;
        } else {
            require(nonce > channel.nonce, "x");
            require(block.number <= channel.disputeBlockTimeout, "f"); //must submit trump w/in original disputeBlockTimeout to prevent endless trump calls. 
        }

        channel.nonce = nonce;
    }

    
    /**
     * Endpoint for when a party is noncompliant/offline and the other party needs to force a settle. Starts a settlment period. 
     * Accepts either a Unconditional/Initial message or a Sharded message. Unconditional/Initial messages will only succeed if there is not a settlment already started. 
     * Sharded messages will only succeed if nonce is higher, and will reset the timeout to what is passed in. Can be called after a settlement has started. 
     * startDispute can be called by owner or partner only. Done to prevent any malicious activity on the part of the watchtowers.
     */
     //Receives a {INITIAL, UNCONDITIONAL, SHARDED, UNCONDITIONALSUBSET} || balanceTotalsMsg. Stores in msgHash = {msgType with deadline(INITIAL), nonce(else) stripped out} || shardDataMsg
    function startDispute(bytes calldata message, bytes calldata signatures, address owner, mapping(uint => Channel) storage channels) external returns(uint channelID, uint32 nonce, MsgType msgType) {
        uint numTokens = uint(uint8(message[NUM_TOKEN]));
        channelID = uint(keccak256(message[1: START_ADDRS + (numTokens * 20)]));     
        Channel storage channel = channels[channelID]; 
        require(channel.exists, "u");
        require(channel.balanceTotalsHash == uint160(bytes20(keccak256(message[message.length - (32 * numTokens): message.length]))), "E"); //MAGICNUMBER NOTE: take last numTokens values, since these are the uint[] balanceTotals
        (nonce, msgType) = disputeStartedChecks(channel, message, signatures, numTokens, owner); //for simiplicity of checks concerning the partners signing addr, we call checkSignatures in here
        
        //properly set the shards, while also checking for overflows of channel balances
        updateShards(channel, message, msgType, numTokens);
        
    }

    function doChecksUpdateShard(mapping(uint => Channel) storage channels, bytes calldata message, uint8[] calldata shardNos) private view returns (uint channelID) {
        require(MsgType(uint8(message[0])) == MsgType.SHARDED, "p");
        uint numTokens = uint(uint8(message[NUM_TOKEN]));
        channelID = uint(keccak256(message[1: START_ADDRS + (numTokens * 20)]));
        require(channels[channelID].exists, "u");
        uint8 numShards = uint8(message[START_ADDRS + (TOKEN_PLUS_BALS_UNIT * numTokens)]);//MAGICNUMBERNOTE: this is numShards, which is stored right at end of the ownerPartnerBals
        for (uint i = 0; i < shardNos.length; i++) {
            require(numShards > shardNos[i], "v");
            if (i != 0) { require(shardNos[i] > shardNos[i - 1]); } //we enforce that shardNos are strictly increasing. Dunno if necessary
        }
        
        require(channels[channelID].msgHash == uint(keccak256(message)), "B");
    }

    //NOTE: dont pass in numTokens bc will stack overflow
    function changeShardStateHelper(bytes calldata message, uint8[] calldata shardNos, uint hashlockPreimage) private view returns (uint) {
        uint numTokens = uint(uint8(message[0]));

        uint numShards = uint(uint8(message[START_ADDRS + (TOKEN_PLUS_BALS_UNIT * numTokens)]));
        ShardState[] memory shardStatesNew = new ShardState[](numShards);
        assembly { calldatacopy(add(shardStatesNew, 32),  add(message.offset, sub(message.length, add(32, numTokens))), numShards) } //store the current shardDataMsgs in shardStatesNew

        uint shardBlockTimeout;
        assembly { shardBlockTimeout := calldataload(sub(add(message.offset, message.length), 32)) } //accesses blockAtDispute
        for (uint i = 0; i < shardNos.length; i++) {
            uint shardPointer = uint(uint8(message[START_ADDRS + (TOKEN_PLUS_BALS_UNIT * 84) + 1 + (shardNos[i] * LEN_SHARD) + 34])); //point this to proper shards tokenIndex, jumpin over tokenBalances, numShards, prior shards, and then tokenIndex, oGoR, amount
            require(block.number <= shardBlockTimeout + uint(uint8(message[shardPointer])) * BLOCKS_PER_HOUR, "e"); //add blockAtDispute + shardblockTimeoutHours * BLOCKS_PER_HOUr
            address partnerAddr;
            assembly { partnerAddr := calldataload(sub(message.offset, 3)) } //MAGICNUMBERNOTE: so that reads up to -3 + 32 = 29, which is where partnerAddr ends in message
        
            // shardMessageIndex = message.length - 32 - (numTokens - shardNos[i]);
            // ShardState shardState = ShardState(uint8(message[shardMessageIndex]));//extract out shard state stored. is the index at which the shard is storing shardState in shardDataMsg
        
            if (uint8(message[shardPointer + 1]) == 1) {
                //TO DO: this may be subject to change whether or not we even have this flag, or even a distinction between turing complete/incomplete. Currently dont.
                // //updateIncludesTuringIncomplete
                // shardPointer += pushForward ? 2 : 34; //point it to either start forwardHashlock, or revertHashlock
                // uint hashlock;
                // assembly { hashlock := calldataload(add(message.offset, shardPointer)) }
                // require(hashlock == uint(keccak256(abi.encodePacked(hashlockPreimage))), "A");

                // //slash if second reveal of a hashlock. Else, update to either pushedForward, reverted. 
                // if ((shardState == ShardState.REVERTED && pushForward) || (shardState == ShardState.PUSHEDFORWARD && !pushForward)) {
                //     shardStateNew = ShardState.SLASHED;
                // } else if (shardState == ShardState.INITIAL) {
                //     shardStateNew = pushForward ? ShardState.PUSHEDFORWARD : ShardState.REVERTED;
                // } else {
                //     revert('m'); //revert if trying to revert already revert, push forward already forward, or do anything with a slashed state
                // }
            } else {
                //nonTuringInc. case. If shard has not been pushed forward; if hashlock given is correct, push forward. But, if less than 1 hour remaining, then slash.
                uint hashlock;
                assembly { hashlock := calldataload(add(message.offset, add(shardPointer, 1))) } //MAGICNUMBERNOTE: 1 is just to jump over shardBlockTimeout
                require(hashlock == uint(keccak256(abi.encodePacked(hashlockPreimage))), "A");
                shardStatesNew[i] = ShardState.PUSHEDFORWARD;
            }
        }
        //construct new msg, swapping in proper value for the updated shard(s)
        return uint(keccak256(abi.encodePacked(message[0: message.length - 32 - numTokens], shardStatesNew, message[message.length - 32: message.length])));
    }


    /**
     * Done to push either push fwd(normal, turing incomplete), or revert(turing incomplete) a shard. 
     * For this call to succeed, there must be a settlement on a Sharded message already in place.
     * Must still call withdraw when timeout ends. Balances are set here, but funds not yet distributed. 
     * This can be called for an array of shardNos provided they all share the same hashlock.
     */
     //message here is the message that was stored for channel.msgHash + shardStateChangeData
     //takes in same message that is stored in msgHash in startDispute, or that has been updated and restored here in changeShardState
    function changeShardState(bytes calldata message, uint hashlockPreimage, uint8[] calldata shardNos, mapping(uint => Channel) storage channels) external returns(uint channelID, uint msgHash) {
        channelID = doChecksUpdateShard(channels, message, shardNos);
        msgHash = changeShardStateHelper(message, shardNos, hashlockPreimage);
        channels[channelID].msgHash = msgHash;
    }


    


    function addShardsInWithdraw(bytes calldata message, BalancePair[] memory shardTokenBals, uint numTokens, uint8 numShards) pure private {
        //we will go through and add all the shard information to shardTokenBals.
        uint shardPointer = START_ADDRS + (TOKEN_PLUS_BALS_UNIT * numTokens) + 1; //points now to tokenIndex of first shard.
        for (uint8 i = 0; i < numShards; i++) {
            ShardState shardState = ShardState(uint8(message[message.length - 32 - (numShards - i)]));
            uint amount;
            bool ownerGiving = uint8(message[shardPointer + 1]) == 1; //jumps shardPointer over tokenIndex
            assembly { amount := calldataload(add(message.offset, add(shardPointer, 2))) } //MAGICNUMBERNOTE: jumps over tokenINdex, ownerGoR
            if ((ownerGiving && (shardState == ShardState.REVERTED || shardState == ShardState.INITIAL)) || (!ownerGiving && shardState == ShardState.PUSHEDFORWARD)) { //} || (ownerControlsHashlock == 0 && shardState == ShardState.SLASHED)) {
                //owner was giving and the funds reverted, so owner gets them back, or owner was receiving and it was pushed through, so owner actually gets them.
                shardTokenBals[i].ownerBalance += amount;
            } else {
                //owner was giving and funds pushed through, so partner gets them, or partner was receiving and reverted, so partner gets them back
                shardTokenBals[i].partnerBalance += amount;
            }
            shardPointer += LEN_SHARD;

            //OLD multitoken per shard code
            // uint8 lenAmounts = 32 * uint8(message[shardPointer + numTokens]); //32 * numAmounts
            // uint8 ownerControlsHashlock = uint8(message[shardPointer + numTokens + 1 + lenAmounts]);//jump over oGOR, numAmounts, amounts[]
            // uint seen = 0;
            // for (uint j = 0; j < numTokens; j++) {
            //     uint amount;
            //     uint8 person = uint8(message[shardPointer]);
            //     if (person == 1 || person == 2) { 
            //         //this token is being traded on.
            //         //ownerGivingOrReceiving must be 1 or 2. If {1, revert/initial} => owner. If {2, revert/initial} => partner. If {2, pushForward} => owner. If {1, pushForward} => partner. If {slashed, ownerControls} => partner. If {slashed, partnerControls => owner}
            //         assembly { amount := calldataload(add(add(shardPointer, add(1, numTokens)), mul(seen, 32))) } //points shardPointer over uint8[], numAmounts byte, to then index into the proper amount in amounts[] 
            //         //giveFundsToOwnerCases:
            //         if ((person == 1 && (shardState == ShardState.REVERTED || shardState == ShardState.INITIAL)) || (person == 2 && shardState == ShardState.PUSHEDFORWARD) || (ownerControlsHashlock == 0 && shardState == ShardState.SLASHED)) {
            //             shardTokenBals[i].ownerBalance += amount;
            //         } else {
            //             //we don't bother checking whether this is going to partner. By process of elim, since not going to owner, must be going to partner
            //             shardTokenBals[i].partnerBalance += amount;
            //         }
            //     seen += 1;
            //     }
            //     shardPointer += 32 * uint8(message[shardPointer - 1]); //jump shardPointer to shard next lenShard byte, add 1 to get it to next oGOR
            // }
        }
    }

    /**
     * Is precisely the message used in the keccak at the end of startDispute, or this same msg with modification from any successful changeShardState calls. If sharded, also has tacked onto the end the shardedDataMsg
     */
    function withdraw(bytes calldata message, mapping(uint => Channel) storage channels, mapping(address => uint) storage tokenAmounts) external returns (uint channelID, uint numTokens) {        
        numTokens = uint(uint8(message[NUM_TOKEN])); 
        channelID = uint(keccak256(message[1: START_ADDRS + (20 * numTokens)]));
        
        Channel storage channel = channels[channelID];    
        require(uint256(keccak256(message)) == channel.msgHash, "B");
        uint8 numShards = eligibleForWithdraw(message, channel, numTokens);
        //all shardBlockTimeouts, disputeBlockTimeout have ended, channel actually exists, it is now safe to send out values
        
        uint startBals = START_ADDRS + (numTokens * 20);
        BalancePair[] memory shardTokenBals = new BalancePair[](numTokens); //this stores owner, partner split for each token.
        assembly { calldatacopy(add(shardTokenBals, 32), add(message.offset, startBals), mul(numTokens, 64)) }  //lets initialize it with the non sharded information stored in message balances right after tokens

        if (numShards > 0) {
            addShardsInWithdraw(message, shardTokenBals, numTokens, numShards);
        }

        //now, we have added all the shardedFunds into the shardTokenBals. Now, we need to go into unsharded token balances, and add in each owner, partner amount
    
        address partnerAddr;
        assembly{ partnerAddr := calldataload(sub(message.offset, 3)) } //MAGICNUMBERNOTE: so that reads up to -3 + 32 = 29, which is where partnerAddr ends in message
        
        address tokenAddress;
        for (uint8 i = 0; i < numTokens; i++) {
            assembly { tokenAddress := calldataload(add(message.offset, add(38, mul(i, 20)))) } //MAGICNUMBERNOTE: bc START_ADDRS is at 50, so first addr ends at 70 - 32 = 38
            //TO DO: could do another check here that no channel overflow, but feels unnecessary bc already been checked, and currently aren't even passing the balanceTotals array.
            if (i == 0 && tokenAddress == NATIVE_TOKEN) {
                payable(partnerAddr).transfer(shardTokenBals[i].partnerBalance);   
            } else {
                IERC20 token = IERC20(tokenAddress);
                token.transfer(partnerAddr, shardTokenBals[i].partnerBalance);
            }
            tokenAmounts[tokenAddress] += shardTokenBals[i].ownerBalance;
        }
        
        //clean up
        delete channels[channelID];
    }
}








//Error Msg Key:
// a: "can't reenter contract"
// b: "either channel does not exist or no settlement is in progress"
// c: can't withdraw yet bc disputeBlockTimeout has not expired
// d: at least one shardBlockTimeout hasn't expired yet
// e: shard has already expired
// f: disputeBlockTimeout has expired; too late to pass new message
// g: only owner can add funds
// h: invalid terminate conditions exist, either sender != owner or lockCount != 0
// i: no 3rd party submission; msg.sender must be owner or partner
// j: failed transferFrom attempt on an IERC20 contract
// k: the msg.value was too small for amount of native token requested in msg
// l: the updated balances are invalid, as they do not sum to that staked into the channel
// m: the shard was either already slashed, or in the nonTuringIncomplete case, pushedForward, or in the TuringIncomplete case, tried to pushForward a fwd, or revert an already rvrt
// n: bad owner sig
// o: bad partner sig
// p: the msg type provided is not one of the accepted msg types for this function
// q: chainID given in the anchor msg does not match block.chainid
// r: signed anchor message contract field does not match address(this)
// s: channel already created
// t: deadline passed
// u: channel does not exist
// v: no such shard
// w: cant process request because there is a settlementInProgress
// x: update nonce is not high enough (either equal or old msg passed). This is also important, bc if say, due to concurrency, two different msgs with same nonce are passed in a Kaladin route,
    // we dont want the one that is going to finalized to be flip flopping back and forth with every startDispute call until disputeBlockTimeout expires.
// y: can't have two of same token
// z: can't sell and buy same token
// A: preimage does not hash to hashlock (either fwd/revert, depending on pushForward bool)
// B: provided msgHash fails
// C: cant use a recycled message!
// D: This channelFunction is not recognized
// E: Provided balanceTotals does not match hash stored on record
// F: shardDataMsg does not equal that which is stored on chain. 
// G: the numAmounts byte in Shard does not accurately represent the size of the amounts.

