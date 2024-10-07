// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function approve(address to, uint256 tokenId) external;

    function getApproved(uint256 tokenId) external view returns (address);

    function setApprovalForAll(address operator, bool _approved) external;

    function isApprovedForAll(address owner, address operator)
        external
        view
        returns (bool);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

abstract contract Pausable is Context {
    bool private _paused;

    constructor() {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    function _pause() internal virtual {
        _paused = true;
    }

    function _unpause() internal virtual {
        _paused = false;
    }
}

contract Ownable is Context {
    address private _owner;

    constructor() {
        _owner = 0x0ceE8381e39f19a72B5091C81A053Fdf01099852;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _owner = newOwner;
    }
}

contract NFTStaking is Ownable, Pausable {
    IERC20 public Token;
    IERC721 public NFT_LEVEL1;
    IERC721 public NFT_LEVEL2;
    IERC721 public NFT_LEVEL3;

    // Address where tax fees are sent
    address public taxReceiver;

    // Deduction percentage (e.g., 2500 = 25.00%)
    uint256 public deductionPercentage = 2500;

    // Minimum amount required for staking (1 ether = 10^18 wei)
    uint256 public minStaking = 1 ether;

    // Maximum amount allowed for staking (60,000 ether = 60,000 * 10^18 wei)
    uint256 public maxStaking = 60_000 ether;

    // Total number of stakers
    uint256 public totalStakers;

    // Total amount of tokens staked
    uint256 public totalStaked;

    // Total number of NFTs staked
    uint256 public totalNFTStaked;

    // Mapping for spam addresses
    mapping(address => bool) public isSpam;

    // Mapping for new stakers
    mapping(address => bool) public newStakers;

    // Boost percentages for NFTs (e.g., 500 = 5.00%)
    mapping(address => uint256) public nftBoosts;

    mapping(uint256 => uint256) public APR_PERCENTAGE;
    mapping(uint256 => uint256) public TIME_STEP;
    mapping(address => mapping(uint256 => UserInfo[])) private Users;

    struct UserInfo {
        uint256 planDuration;
        uint256 amount;
        uint256 NFTids;
        uint256 startTime;
        uint256 endTime;
        uint256 withdrawn;
        address NFT;
        string userNFTIDsLevel;
        bool hasHarvested;
    }

    event Deposit(
        address indexed to,
        address indexed from,
        uint256 amount,
        uint256 day,
        uint256 time
    );
    event Harvest(
        address indexed user,
        uint256 NFT,
        uint256 harvestedAmount,
        uint256 totalDeduction,
        uint256 planDuration
    );

    constructor() {
        Token = IERC20(0x7Fd4Abc178a66E26711658763654A041940C75A9);
        NFT_LEVEL1 = IERC721(0x1Ed1df0dca15A7D26CCc1E80984719ea71De7cE4);
        NFT_LEVEL2 = IERC721(0x012B42fb9Bb510a049f66dec225D4a2466AFcae6);
        NFT_LEVEL3 = IERC721(0x8761Ca4aEdc30c4de6E56141161eb0874640925E);
        taxReceiver = owner();

        // Set NFT boost percentages for each level of NFTs
        nftBoosts[address(NFT_LEVEL1)] = 5_00; // Boost 5% for level 1 NFTs
        nftBoosts[address(NFT_LEVEL2)] = 10_00; // Boost 10% for level 2 NFTs
        nftBoosts[address(NFT_LEVEL3)] = 15_00; // Boost 15% for level 3 NFTs

        // Set APR (Annual Percentage Rate) values for different plan durations
        APR_PERCENTAGE[14] = 100_41; // 14-day lock: = 0.41%
        APR_PERCENTAGE[30] = 101_66; // 30-day lock: = 1.66%
        APR_PERCENTAGE[60] = 105_00; // 60-day lock: = 5 %
        APR_PERCENTAGE[90] = 112_50; // 90-day lock: = 12.5%

        // Set time steps for dividend calculations for each plan duration
        TIME_STEP[14] = 14 days; // Time step for 14-day plan
        TIME_STEP[30] = 30 days; // Time step for 30-day plan
        TIME_STEP[60] = 60 days; // Time step for 60-day plan
        TIME_STEP[90] = 90 days; // Time step for 90-day plan
    }

    function farm(
        uint256 _amount,
        uint256 _lockableDays,
        uint256 _tokenID,
        address _nftAddress
    ) external whenNotPaused {
        require(!isSpam[msg.sender], "Account is flagged as spam");
        require(_amount >= minStaking, "Amount below minimum staking");
        require(_amount <= maxStaking, "Amount above maximum staking");
        require(APR_PERCENTAGE[_lockableDays] > 0, "Invalid lockable days");
        require(
            NFT_LEVEL1 == IERC721(_nftAddress) ||
                NFT_LEVEL2 == IERC721(_nftAddress) ||
                NFT_LEVEL3 == IERC721(_nftAddress),
            "Invalid NFT address"
        );

        uint256 lockableDays = TIME_STEP[_lockableDays];

        Token.transferFrom(msg.sender, address(this), _amount);
        IERC721(_nftAddress).transferFrom(msg.sender, address(this), _tokenID);

        string memory nftLevel;
        if (NFT_LEVEL1 == IERC721(_nftAddress)) {
            nftLevel = "Level 1";
        } else if (NFT_LEVEL2 == IERC721(_nftAddress)) {
            nftLevel = "Level 2";
        } else if (NFT_LEVEL3 == IERC721(_nftAddress)) {
            nftLevel = "Level 3";
        }

        UserInfo memory userInfo = UserInfo({
            planDuration: _lockableDays,
            amount: _amount,
            NFTids: _tokenID,
            startTime: block.timestamp,
            endTime: block.timestamp + lockableDays,
            withdrawn: 0,
            NFT: _nftAddress,
            userNFTIDsLevel: nftLevel,
            hasHarvested: false
        });

        Users[msg.sender][_lockableDays].push(userInfo);

        if (!newStakers[msg.sender]) {
            totalStakers++;
            newStakers[msg.sender] = true;
        }
        totalStaked += _amount;
        totalNFTStaked++;

        emit Deposit(
            msg.sender,
            address(this),
            _amount,
            _lockableDays,
            block.timestamp
        );
    }

    function harvest(uint256 planDuration, uint256 index)
        external
        whenNotPaused
    {
        require(!isSpam[msg.sender], "Account is spam!");

        UserInfo[] storage userDeposits = Users[msg.sender][planDuration];
        require(index < userDeposits.length, "Invalid deposit index");

        UserInfo storage deposit = userDeposits[index];
        require(!deposit.hasHarvested, "Already harvested for this deposit");

        uint256 totalHarvestedAmount = 0;
        uint256 totalDeduction = 0;

        if (block.timestamp < deposit.endTime) {
            uint256 deduction = (deposit.amount * deductionPercentage) / 100_00;
            totalHarvestedAmount = deposit.amount - deduction;
            totalDeduction = deduction;

            if (totalDeduction > 0) {
                Token.transfer(taxReceiver, totalDeduction);
            }

            Token.transfer(msg.sender, totalHarvestedAmount);
        } else {
            totalHarvestedAmount = getUserDividends(
                msg.sender,
                planDuration,
                index
            );

            Token.transfer(msg.sender, totalHarvestedAmount);
        }

        IERC721(deposit.NFT).transferFrom(
            address(this),
            msg.sender,
            deposit.NFTids
        );

        deposit.hasHarvested = true;
        deposit.withdrawn += totalHarvestedAmount;

        emit Harvest(
            msg.sender,
            deposit.NFTids,
            totalHarvestedAmount,
            totalDeduction,
            planDuration
        );
    }

    function getUserDividends(
        address _user,
        uint256 _planDuration,
        uint256 index
    ) public view returns (uint256 totalDividends) {
        UserInfo[] storage userDeposits = Users[_user][_planDuration];

        if (
            userDeposits.length == 0 ||
            index >= userDeposits.length ||
            userDeposits[index].hasHarvested
        ) {
            return 0;
        }

        UserInfo storage selectedDeposit = userDeposits[index];
        uint256 timeElapsed = block.timestamp - selectedDeposit.startTime;

        address userNFT = selectedDeposit.NFT;
        uint256 boostPercentage = nftBoosts[userNFT];

        uint256 APR = APR_PERCENTAGE[_planDuration] + boostPercentage;

        uint256 maxDividends = (selectedDeposit.amount * APR) / 100_00;

        if (block.timestamp < selectedDeposit.endTime) {
            totalDividends =
                (selectedDeposit.amount * APR * timeElapsed) /
                (100_00 * TIME_STEP[_planDuration]);
        } else {
            totalDividends = maxDividends;
        }

        if (selectedDeposit.withdrawn + totalDividends > maxDividends) {
            totalDividends = maxDividends - selectedDeposit.withdrawn;
        }

        return totalDividends;
    }

    function futureRewards(address _add, uint256 _lockableDays)
        public
        view
        returns (uint256 reward, uint256 claimedAmount)
    {
        uint256 Reward = 0;
        uint256 apyPercent = APR_PERCENTAGE[_lockableDays];
        uint256 claimed = 0;

        for (uint256 z = 0; z < Users[_add][_lockableDays].length; z++) {
            UserInfo memory user = Users[_add][_lockableDays][z];
            uint256 elapsedTime = block.timestamp - user.startTime;
            address userNFT = user.NFT;
            uint256 boostPercentage = nftBoosts[userNFT];
            uint256 totalAPR = apyPercent + boostPercentage;
            uint256 maxAmount = (user.amount * totalAPR) / 100_00;
            uint256 currentReward;
            if (block.timestamp < user.endTime) {
                currentReward =
                    (user.amount * totalAPR * elapsedTime) /
                    (100_00 * TIME_STEP[_lockableDays]);
            } else {
                currentReward = maxAmount;
            }
            uint256 unclaimedReward = currentReward > user.withdrawn
                ? currentReward - user.withdrawn
                : 0;
            Reward += unclaimedReward;
            claimed += user.withdrawn;
        }

        return (Reward, claimed);
    }

    function getUserDepositInfo(
        address _user,
        uint256 _planDuration,
        uint256 _index
    )
        public
        view
        returns (
            uint256 planDuration,
            uint256 amount,
            uint256 NFTids,
            uint256 startTime,
            uint256 endTime,
            uint256 withdrawn,
            address NFT,
            string memory userNFTIDsLevel,
            bool hasHarvested
        )
    {
        UserInfo[] storage deposits = Users[_user][_planDuration];
        require(_index < deposits.length, "Invalid index");

        UserInfo storage deposit = deposits[_index];
        return (
            deposit.planDuration,
            deposit.amount,
            deposit.NFTids,
            deposit.startTime,
            deposit.endTime,
            deposit.withdrawn,
            deposit.NFT,
            deposit.userNFTIDsLevel,
            deposit.hasHarvested
        );
    }

    function getUserStakesCount(address _user, uint256 _planDuration)
        public
        view
        returns (uint256)
    {
        return Users[_user][_planDuration].length;
    }

    function getUserStakedPlans(address userAddress)
        external
        view
        returns (uint256[] memory)
    {
        UserInfo[] storage userDeposits;
        uint256 maxPlans = 90;
        bool[] memory hasStakedPlan = new bool[](maxPlans + 1);

        for (uint256 i = 0; i <= maxPlans; i++) {
            userDeposits = Users[userAddress][i];
            if (userDeposits.length > 0) {
                hasStakedPlan[i] = true;
            }
        }

        uint256 stakedPlanCount = 0;
        for (uint256 i = 0; i <= maxPlans; i++) {
            if (hasStakedPlan[i]) {
                stakedPlanCount++;
            }
        }

        uint256[] memory uniquePlans = new uint256[](stakedPlanCount);
        uint256 index = 0;
        for (uint256 i = 0; i <= maxPlans; i++) {
            if (hasStakedPlan[i]) {
                uniquePlans[index] = i;
                index++;
            }
        }

        return uniquePlans;
    }

    function withdrawTokens(address _tokenAddress, uint256 _amount)
        external
        onlyOwner
    {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than zero");

        IERC20 token = IERC20(_tokenAddress);
        uint256 contractBalance = token.balanceOf(address(this));
        require(_amount <= contractBalance, "Insufficient contract balance");

        token.transfer(msg.sender, _amount);
    }

    function withdrawNFT(IERC721 _nftContract, uint256 _tokenId)
        external
        onlyOwner
    {
        require(
            address(_nftContract) != address(0),
            "Invalid NFT contract address"
        );
        require(
            _nftContract.ownerOf(_tokenId) == address(this),
            "Contract does not own this NFT"
        );

        _nftContract.safeTransferFrom(address(this), msg.sender, _tokenId);
    }

    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        payable(owner()).transfer(balance);
    }

    function setToken(IERC20 _token) external onlyOwner {
        Token = _token;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setSpamStatus(address _address, bool _status) external onlyOwner {
        isSpam[_address] = _status;
    }

    function updateTaxReceiver(address _newTaxReceiver) external onlyOwner {
        taxReceiver = _newTaxReceiver;
    }

    function updateStakingLimits(uint256 _min, uint256 _max)
        external
        onlyOwner
    {
        minStaking = _min;
        maxStaking = _max;
    }

    function updateDeductionPercentage(uint256 _percentage) external onlyOwner {
        deductionPercentage = _percentage;
    }

    function setNftBoost(address nftAddress, uint256 boostPercentage)
        public
        onlyOwner
    {
        nftBoosts[nftAddress] = boostPercentage;
    }

    function setAPR_PERCENTAGE(uint256 _planDuration, uint256 _aprPercentage)
        public
        onlyOwner
    {
        APR_PERCENTAGE[_planDuration] = _aprPercentage;
    }

    function setTIME_STEP(uint256 _planDuration, uint256 _timeStep)
        public
        onlyOwner
    {
        TIME_STEP[_planDuration] = _timeStep;
    }

    function setNFTContracts(
        IERC721 _nftLevel1,
        IERC721 _nftLevel2,
        IERC721 _nftLevel3
    ) external onlyOwner {
        NFT_LEVEL1 = _nftLevel1;
        NFT_LEVEL2 = _nftLevel2;
        NFT_LEVEL3 = _nftLevel3;
    }
}
