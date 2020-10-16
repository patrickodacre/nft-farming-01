# NFT Farming - Attempt 1

This is a place for me to explore and learn more about NFT farming.

At first, I didn't get it. But now I'm seeing that there is definitely a large number of people that enjoy digital collectables. 

## Run Locallly

Tests:

```shell

npx buidler test

```

## Journal

### Oct 16 - Reward Distribution && Resilience

I've been at this a few days now, and it's time I share some of the excellent resources I've come across and the feedback I've received.

**Reward Distribution**

I've had to devote a lot of time to understanding how to handle distributing rewards. At the time of this writing, I've opted to keep it simple and grant 1 rewarded token for every token staked. In the future I think I would have to integrate an exchange of some sort, so all tokens staked will be treated somewhat equally. I believe Chainlink oracles can be used for something like this.

I've also spent a lot of time researching the different coding strategies that can be used to issue rewards. In this search I came across this interesting write up:

[Scalable Reward Distribution](https://uploads-ssl.webflow.com/5ad71ffeb79acc67c8bcdaba/5ad8d1193a40977462982470_scalable-reward-distribution-paper.pdf)

The write up here inspired the implementation you see in this app. You can also look to [this commit](https://github.com/patrickodacre/nft-farming-01/commit/333a8746eb51c8d65547c58ae86db960aac5e3d2** for my reason for doing things the way I did.

**Resilience**

I posted the above commit to a Discord server I frequent - CryptoDevs - and I received some great feedback. Thank you, Killari.

Here is the feedback I received:

> this is dangerous: for (uint i = 0; i < a.tokens.length; i ++) {
> and this: for (uint256 j = 0; j < a.deposits[token].length; j++) {
> owner of the contract can stop everyone from withdrawing
> tokenIsAllowed should use mapping and not array
> you should always avoid unbounded loops. As the length of the loop grows, 
> the more gas it consumes. In the end it will consume more gas than you can 
> spend in a single block and you cannot call that function ever after

Let me break it down a bit more, as the above points got flushed out a lot in chat.

My use of "unbounded" loops was a danger because the size of the array can grow to a point where a full iteration would be so expensive as to make execution of the function impossible. 

That is what Killari meant here:

> owner of the contract can stop everyone from withdrawing

Looking at `claimRewards()`, with an unbounded loop the array could get so large as to prevent anyone from ever claiming rewards simply because the function would run out of gas before fully executing, thus preventing the execution altogether. Not good.

Instead, it was recommended that I pass the function an array of tokens for which to claim rewards. This way, the CALLER has full control over how much work the function does - ie: the loop becomes bounded. Since the contract is permanent code, it is crucial that minor adjustments be possible from the calling client, eg: the UI. The end-user doesn't have to know this is what is happening, of course; I don't have to force the end-user to click each staked token to claim rewards. I can hide all of that away in the client-side JavaScript. The point is that the amount of work the contract code has to do can be fine-tuned after deployment, avoiding such a disaster as a contract function that can't execute.

This reminds me again that the blockchain / Ethereum has finite resources and they that can't be scaled up by just spinning up some new instances of the EVM.
