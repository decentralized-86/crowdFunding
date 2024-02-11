//SPDX-License-Identifier : MIT
pragma solidity 0.8.20;

// import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ERC20CampaignTemplate.sol";

contract CampaignManager {
    enum CampaignState {
        Uninitialized,
        Pending,
        Active,
        Paused,
        Successful,
        Failed,
        Cancelled,
        Completed
    }

    struct Campaign {
        uint256 campaignID;
        address campaignCreator;
        uint256 fundingGoal;
        uint256 investorsVoteCount;
        uint256 totalInvestors;
        uint256 currentBalance;
        uint256 finishAt;
        bool hasApproved;
        bool hasRequestedForApproval;
        CampaignState state;
        string description;
        string name;
        address erc20Address;
    }

    struct Contribution {
        uint256 amount;
        uint256 usdValue;
        string currency;
    }

    AggregatorV3Interface internal constant priceFeedMATIC = AggregatorV3Interface(0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada);
AggregatorV3Interface internal constant priceFeedUSDC = AggregatorV3Interface(0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0);
AggregatorV3Interface internal constant priceFeedDAI = AggregatorV3Interface(0x0FCAa9c899EC5A91eBc3D5Dd869De833b06fB046);

    mapping(uint256 => mapping(address => Contribution)) private contributions;
    address private immutable owner;
    mapping(uint256 => Campaign) public campaigns;
    uint256 private campaignCount;

    event CampaignCreated(
        uint256 campaignID, address campaignCreator, uint256 fundingGoal, uint256 duration, string description
    );
    event CampaignActivated(uint256 campaignID);
    event CampaignTerminated(uint256 campaignID);
    event FundDeposited(uint256 campaignID, address depositer, uint256 depositedAmount, address tokenAddress);
    event RefundProcessed(uint256 campaignID, address receiver, uint256 refundAmount);

    error mustBeValid();
    error onlyowner();

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert onlyowner();
        }
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function createCampaign(
    uint256 _fundingGoal, 
    uint256 _duration, 
    string memory _description, 
    string memory _name
) external {
    if (_fundingGoal <= 0 || _duration <= 0) revert mustBeValid();
    if(bytes(_description).length == 0 || bytes(_name).length == 0) revert mustBeValid();

    uint256 newCampaignID = ++campaignCount;
    require(campaigns[newCampaignID].state == CampaignState.Uninitialized, "Campaign already exists");

    CampaignToken token = new CampaignToken(_name, _name); // Ensure this line is correct and CampaignToken can be initialized like this

    Campaign memory newCampaign = Campaign({
        campaignID: newCampaignID,
        campaignCreator: msg.sender,
        fundingGoal: _fundingGoal,
        investorsVoteCount: 0,
        totalInvestors: 0,
        currentBalance: 0,
        finishAt: block.timestamp + _duration,
        hasApproved: false,
        hasRequestedForApproval: false,
        state: CampaignState.Pending,
        description: _description,
        name: _name,
        erc20Address: address(token)
    });

    campaigns[newCampaignID] = newCampaign;
    emit CampaignCreated(newCampaignID, msg.sender, _fundingGoal, _duration, _description);
}


    function activateProject(uint256 _campaignID) external onlyOwner {
        Campaign storage campaign = campaigns[_campaignID];
        require(campaign.state == CampaignState.Pending, "Campaign must be in pending state");
        require(campaign.finishAt > block.timestamp, "Campaign duration must be in the future");
        campaign.state = CampaignState.Active;
        emit CampaignActivated(_campaignID);
    }

    function updateCampaign(uint256 _campaignID, string memory _newDescription, uint256 _newFundingGoal) external {
        Campaign storage campaign = campaigns[_campaignID];
        require(msg.sender == campaign.campaignCreator || msg.sender == owner, "Only creator or owner can update");
        require(campaign.state == CampaignState.Pending, "Can only update pending campaigns");
        campaign.description = _newDescription;
        campaign.fundingGoal = _newFundingGoal;
    }

    function changeCampaignState(uint256 _campaignID, CampaignState _newState) external onlyOwner {
        Campaign storage campaign = campaigns[_campaignID];
        require(_newState != CampaignState.Uninitialized, "Invalid state");
        campaign.state = _newState;
    }

    function terminateCampaign(uint256 _campaignID) external {
        Campaign storage campaign = campaigns[_campaignID];
        require(msg.sender == campaign.campaignCreator || msg.sender == owner, "Only creator or owner can terminate");
        require(
            campaign.state != CampaignState.Completed && campaign.state != CampaignState.Cancelled,
            "Campaign already terminated"
        );
        campaign.state = CampaignState.Cancelled;
        emit CampaignTerminated(_campaignID);
    }

    function voteForWithdrawal(uint256 _campaignID) external {
        Campaign storage campaign = campaigns[_campaignID];
        require(campaign.state == CampaignState.Completed, "Campaign is not completed");
        require(block.timestamp > campaign.finishAt, "Campaign funding period has not ended");
        require(contributions[_campaignID][msg.sender].amount > 0, "Investor must have be invested in the campaing");
        campaign.investorsVoteCount += 1; 
    }

    function depositFunds(uint256 _campaignID, uint256 _investmentAmount, string memory _tokenSymbol)
        external
        payable
    {
        Campaign storage campaign = campaigns[_campaignID];
        require(campaign.state == CampaignState.Active, "Campaign is not active");
        require(block.timestamp < campaign.finishAt, "Campaign funding period has ended");

        require(contributions[_campaignID][msg.sender].amount == 0, "Investor can only contribute once");
        uint256 dollarValue;
        if (keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked(""))) {
            uint maticPriceInUSD = getLatestPrice(address(priceFeedMATIC));
            dollarValue = (msg.value * maticPriceInUSD) / 1e8;
        } else {
            address stablecoinAddress = getStablecoinAddress(_tokenSymbol);
            IERC20 stablecoin = IERC20(stablecoinAddress);
            require(
                stablecoin.transferFrom(msg.sender, address(this), _investmentAmount), "Failed to transfer ERC20 tokens"
            );
            dollarValue = _investmentAmount;
        }
        require((campaign.currentBalance + dollarValue) <= campaign.fundingGoal, "Exceeds funding goal");

        uint256 tokensToMint = dollarValue * 100;
        CampaignToken campaignToken = CampaignToken(campaign.erc20Address);
        campaignToken.mint(msg.sender, tokensToMint);

        campaign.currentBalance += dollarValue;
        campaign.totalInvestors += 1;
        contributions[_campaignID][msg.sender] =
            Contribution({amount: _investmentAmount, usdValue: dollarValue, currency: _tokenSymbol});

        emit FundDeposited(_campaignID, msg.sender, dollarValue, campaign.erc20Address);
    }

    function requestWithdrawFund(uint256 _campaignID) external {
        Campaign storage campaign = campaigns[_campaignID];
        require(campaign.state == CampaignState.Active, "Campaign is not active");
        require(block.timestamp > campaign.finishAt, "Campaign funding period has not ended");
        require(campaign.campaignCreator == msg.sender, "Not the campaign creator");
        require(campaign.investorsVoteCount > (campaign.totalInvestors / 2), "Must have 50% investor's approval");
        campaign.hasRequestedForApproval = true;

    }

    function approveWithdrawFund(uint256 _campaignID) external {
        Campaign storage campaign = campaigns[_campaignID];
        require(msg.sender == owner, "Not owner");
        require(campaign.hasRequestedForApproval, "Not requested for approval");
        campaign.hasRequestedForApproval = false;
        campaign.hasApproved = true;
    }

    function withdrawFunds(uint256 _campaignID) external {
    Campaign storage campaign = campaigns[_campaignID];
    require(campaign.state == CampaignState.Active, "Campaign is not active");
    require(block.timestamp > campaign.finishAt, "Campaign funding period has not ended");
    require(campaign.campaignCreator == msg.sender, "Not the campaign creator");
    require(campaign.investorsVoteCount > (campaign.totalInvestors / 2), "Must have 50% investor's approval");
    require(campaign.hasApproved, "Not approved by owner");

    uint totalFunds = campaign.currentBalance;
    uint fees = (totalFunds * 10) / 100; // Calculate a 10% fee
    uint remainFunds = totalFunds - fees; // Remaining funds after fees

    // Transfer fees to the owner
    (bool feeSent,) = payable(owner).call{value: fees}("");
    require(feeSent, "Fee transfer failed");

    // Check the currency used in the contribution to decide how to refund
    Contribution storage contribution = contributions[_campaignID][msg.sender];
    if (keccak256(abi.encodePacked(contribution.currency)) == keccak256(abi.encodePacked("ETH"))) {
        // If the currency is ETH, send the remaining funds directly
        (bool sent,) = msg.sender.call{value: remainFunds}("");
        require(sent, "Refund transfer failed");
    } else {
        // For ERC20 tokens, convert the remaining funds back to the token and send
        IERC20 token = IERC20(getStablecoinAddress(contribution.currency));
        // Assuming 1 USD = 1 Token for simplicity, adjust accordingly based on your token's value
        require(token.transfer(msg.sender, remainFunds), "Token transfer failed");
    }

    // Adjust the campaign's current balance
    campaign.currentBalance -= totalFunds;
}


    function withdrawRefund(uint256 _campaignID) external {
        Campaign storage campaign = campaigns[_campaignID];
        require(campaign.state == CampaignState.Cancelled, "Campaign is not cancelled");

        Contribution storage contribution = contributions[_campaignID][msg.sender];
        require(contribution.amount > 0, "No funds invested");

        uint256 refundAmount = (contribution.usdValue * campaign.currentBalance) / campaign.fundingGoal;
        require(refundAmount <= campaign.currentBalance, "Refund amount exceeds available balance");

        campaign.currentBalance -= refundAmount;
        if (keccak256(abi.encodePacked(contribution.currency)) == keccak256(abi.encodePacked(""))) {
            (bool sent,) = msg.sender.call{value: refundAmount}("");
            require(sent, "Refund transfer failed");
        } else {
            IERC20 token = IERC20(getStablecoinAddress(contribution.currency));
            uint price = getLatestPrice(address(priceFeedUSDC));
            require(token.transfer(msg.sender, refundAmount * price), "Refund transfer failed");
        }
        delete contributions[_campaignID][msg.sender];
        emit RefundProcessed(_campaignID, msg.sender, refundAmount);
    }

    function getLatestPrice(address priceFeedAddress) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function getStablecoinAddress(string memory _tokenSymbol) internal pure returns (address) {
        if (keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("USDC"))) {
            return address(priceFeedUSDC);
        } else if (keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("DAI"))) {
            return address(priceFeedDAI);
        } else {
            
            revert("Unsupported stablecoin");
        }
    }
}
