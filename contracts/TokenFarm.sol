// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.8.0;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Holder.sol";
/* import "@openzeppelin/contracts/math/SafeMath.sol"; */
import "@openzeppelin/contracts/access/Ownable.sol";
import "./EQToken.sol";
import "@nomiclabs/buidler/console.sol";

contract TokenFarm is ERC1155Holder, ChainlinkClient, Ownable {

    /* === Structs === */

    struct Deposit {
        // the reward index when this deposit last had
        // rewards calculated on it.
        uint256 rewardFromIndex;
        uint256 amount;
    }

    struct Account {
        bool active;
        // a list of tokens that have been staked
        // both presently and in the past
        address[] tokens;
        // keep track of which tokens are presently staked
        // tokenAddress => bool
        mapping(address => bool) tokenStaked;
        // tokenAddress => array of deposits for this token
        mapping(address => Deposit[]) deposits;
    }

    /* === Arrays, etc. === */

    string public name = "EQ Token Farm";
    EQToken public eqToken;

    uint256 public totalStake;
    address[] public stakers;
    uint256[] public rewards;

    /* === Mappings === */

    // ERC20 token > (msg.sender => balance)
    mapping(address => mapping(address => uint256)) public stakingBalance;

    // userAccountAddress =>
    mapping(address => Account) accounts;
    mapping(address => uint256) public uniqueTokensStaked;

    // tokenAddress =>
    mapping(address => bool) public allowedTokens;

    /* === Events === */

    event TokensStaked(address indexed staker, uint256 amount, uint256 balance);
    event TokensUnstaked(address indexed staker, uint256 amount);

    constructor(address _eqTokenAddress) public
    {
        eqToken = EQToken(_eqTokenAddress);
    }

    /* === Tokens === */

    function authorizeToken(address token) public
        onlyOwner
    {
        allowedTokens[token] = true;
    }

    function stakedTokens() public
        view
        returns (address[] memory)
    {
        Account storage a = accounts[msg.sender];

        address[] memory activeTokens = new address[](uniqueTokensStaked[msg.sender]);
        uint256 counter = 0;

        for (uint256 i = 0; i < a.tokens.length; i++) {
            address token = a.tokens[i];

            if (a.tokenStaked[token]) {
                activeTokens[counter] = token;
                counter++;
            }
        }

        return activeTokens;
    }

    // stakeTokens changes ownership of the staker's 3rd-party ERC20 token
    // to that of this contact, then records that staked amount here in this contract.
    // This contract is just holding ownership of those 3rd-party tokens
    // (ie: the balance on the 3rd-party token contract) temporarily;
    // the staker can UNSTAKE those tokens 3rd-party tokens,
    // reclaiming ownership, at any time.
    // users can stake ERC20 tokens only.
    function stakeTokens(uint256 _amount, address token) public
    {
        // Require amount greater than 0
        require(_amount > 0, "TokenFarm: Staked amount cannot be 0");
        require(tokenIsAllowed(token), "TokenFarm: Token cannot be staked. Token not supported.");

        totalStake = totalStake.add(_amount);
        IERC20(token).transferFrom(msg.sender, address(this), _amount);

        // if this is the FIRST time the user has staked ANY token,
        // we need to add this user to the list of stakers
        if (uniqueTokensStaked[msg.sender] == 0) {
            stakers.push(msg.sender);
        }

        // if the current balance for this token / user is 0,
        // then this is the first time the user
        // has staked this particular token, and we should
        // increment our number of unique tokens this user has staked
        if (stakingBalance[token][msg.sender] == 0) {
            uniqueTokensStaked[msg.sender] = uniqueTokensStaked[msg.sender] + 1;
        }

        stakingBalance[token][msg.sender] = stakingBalance[token][msg.sender].add(_amount);

        // update the Account record for the user
        {
            Account storage account = accounts[msg.sender];
            account.active = true;
            // each deposit is recorded separately, so rewards can
            // be calculated accurately
            account.deposits[token].push(Deposit(rewards.length, _amount));

            // track unique tokens staked
            if (!account.tokenStaked[token]) {
                account.tokenStaked[token] = true;
                account.tokens.push(token);
            }
        }

        emit TokensStaked(msg.sender, _amount, stakingBalance[token][msg.sender]);
    }

    // Unstaking Tokens (Withdraw)
    function unstakeTokens(address token) public
    {

        // update the Account record for the user
        {
            Account storage account = accounts[msg.sender];

            require(account.deposits[token].length > 0, "TokenFarm: You don't have any tokens to unstake.");

            // each deposit is recorded separately, so rewards can
            // be calculated accurately
            Deposit storage lastDeposit = account.deposits[token][account.deposits[token].length - 1];

            // if there are no rewards disributed, then we're good to go;
            // or if there ARE rewards, we need to make sure the users have collected them.
            require(rewards.length == 0 || lastDeposit.rewardFromIndex > rewards.length, "TokenFarm: You have unclaimed rewards.");

            // now that we know all rewards have been paid for
            // deposits made with this token, we can delete all deposits.
            // The total stake was recorded in stakingBalance, so we don't
            // need this info to know how much to unstake.
            delete account.deposits[token];

            // at this time we won't update the staked tokens array,
            // but only set this token as now "unstaked"
            if (account.tokenStaked[token]) {
                account.tokenStaked[token] = false;
            }
        }

        // unstake the full staking balance for this token
        {
            uint256 balance = stakingBalance[token][msg.sender];
            require(balance > 0, "TokenFarm: Staking balance cannot be 0");

            IERC20(token).transfer(msg.sender, balance);
            stakingBalance[token][msg.sender] = 0;

            uniqueTokensStaked[msg.sender] = uniqueTokensStaked[msg.sender].sub(1);

            totalStake = totalStake.sub(balance);
        }
    }

    function updateUniqueTokensStaked(address user, address token) internal
    {
        if (stakingBalance[token][user] == 0) {
            uniqueTokensStaked[user] = uniqueTokensStaked[user] + 1;
        }
    }

    /* === Rewards === */

    // distributeRewards doesn't actually distribute the reward
    // to all stakers; rather, it records the rewards "earned" for the
    // entire staked pool of funds so individual rewards can be calculated
    // when an account wants to view / claim their reward.
    // TODO: At this point I'm only USING the number of rewards
    // distributed ie: the length of this array and the indexes;
    // but I'm recording the total rewards for later use.
    // TODO: implement a way for users to get rewarded for their own
    // stake, as well as for the growth of the stake pool in general.
    // TODO: encourage retention
    function distributeRewards() public
        onlyOwner
    {

        uint256 previousReward;

        if (rewards.length > 0) {
            previousReward = rewards[rewards.length-1];
        }

        // TODO: should rewards be distributed 1:1 on
        // current total number of staked tokens?
        rewards.push(previousReward.add(totalStake));
    }

    function getAccountRewards(address[] memory tokens) public
        view
        returns (uint256)
    {
        return _checkReward(msg.sender, tokens);
    }

    function _checkReward(address staker, address[] memory tokens) private
        view
        returns (uint256)
    {

        Account storage a = accounts[staker];

        uint256 totalPortionOfRewards;

        // check deposits for each token type staked
        for (uint i = 0; i < tokens.length; i ++) {

            address token = tokens[i];

            // we use this mapping to keep track of
            // which tokens are currently being staked
            if (! a.tokenStaked[token]) {
                continue;
            }

            // for each deposit calc rewards from the rewardFromIndex
            // which is the first reward distributed since the last
            // time rewards were calculated on the deposit
            for (uint256 j = 0; j < a.deposits[token].length; j++) {
                Deposit memory d = a.deposits[token][j];

                // no rewards have been distributed since this deposit.
                // eg: the next reward should be from index 2, but there
                // are only two rewards distributed ie: indexes 0,1 / length 2
                // 2 == 2; therefore skip this deposit
                if (d.rewardFromIndex >= rewards.length) {
                    continue;
                }

                // how many distributions since the last time we checked?
                // TODO: we're recording the value of these rewards,
                // but we're not using those values, yet.
                uint256 distributionsSinceLastTimeChecked = rewards.length - d.rewardFromIndex;

                // TODO: More complex reward system?
                // this assumes just a 1 reward token for every token staked
                totalPortionOfRewards = totalPortionOfRewards.add(d.amount.mul(distributionsSinceLastTimeChecked));
            }
        }

        return totalPortionOfRewards;
    }

    function claimRewards(address[] memory tokens) public
    {

        address staker = msg.sender;

        Account storage a = accounts[staker];

        require(a.active, "TokenFarm: Account isn't active. No tokens are staked.");

        // mint the rewarded tokens:
        {
            uint256 totalPortionOfRewards = _checkReward(staker, tokens);

            // no rewards? no need to proceed with anything here.
            require(totalPortionOfRewards > 0, "TokenFarm: No rewards.");

            eqToken.mintPlatinumFor(staker, totalPortionOfRewards);
        }

        // reset all rewardFromIndexes so next claimRewards
        // only grants rewards that haven't yet been granted.
        {
            for (uint i = 0; i < tokens.length; i ++) {

                address token = tokens[i];

                // the 'tokens' array has all tokens
                // that have ever been staked by this account,
                // so we have to skip those that aren't being staked
                // at this time.
                if (! a.tokenStaked[token]) {
                    continue;
                }

                for (uint256 j = 0; j < a.deposits[token].length; j++) {
                    Deposit storage d = a.deposits[token][j];
                    // reset
                    d.rewardFromIndex = rewards.length;
                }
            }
        }
    }

    /* === Utility === */

    function tokenIsAllowed(address token) public
        view
        returns (bool)
    {
        return allowedTokens[token];
    }
}
