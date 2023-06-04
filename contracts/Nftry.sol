// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC721A.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Nftry is Ownable {
    struct Listing {
        address owner;
        uint depositFee;
        uint fixedFee;
        uint usageFee;
        bool inUse;
        address borrower;
        uint borrowTime;
        uint lastClaim;
    }

    // nft address & token id
    mapping(address => mapping(uint => Listing)) listings;
    mapping(address => mapping(uint => uint)) fixedFees;

    // for testnet custom USDC: 0x9758211252cE46EEe6d9685F2402B7DdcBb2466d
    address public paymentToken;

    event NftListed(address indexed nftAddress, uint tokenId, address owner);
    event NftDelisted(
        address indexed nftAddress,
        uint indexed tokenId,
        address owner
    );

    event FixedFeeClaimed(
        address indexed nftAddress,
        uint indexed tokenId,
        address owner,
        uint fee
    );

    event UsageFeeClaimed(
        address indexed nftAddress,
        uint indexed tokenId,
        address owner,
        uint fee
    );

    event NftBorrowed(
        address indexed nftAddress,
        uint indexed tokenId,
        address borrower
    );

    event NftReturned(
        address indexed nftAddress,
        uint indexed tokenId,
        address borrower
    );

    constructor(address _paymentToken) {
        paymentToken = _paymentToken;
    }

    function setPaymentToken(address _paymentToken) external onlyOwner {
        paymentToken = _paymentToken;
    }

    // =============================================================
    //                        For NFT Lender
    // =============================================================
    function list(
        address nftAddress,
        uint tokenId,
        uint depositFee,
        uint fixedFee,
        uint usageFee
    ) external {
        require(
            IERC721A(nftAddress).ownerOf(tokenId) == msg.sender,
            "The NFT is not owned by the 'from' address"
        );

        IERC721A(nftAddress).transferFrom(msg.sender, address(this), tokenId);

        Listing storage listing = listings[nftAddress][tokenId];
        listing.owner = msg.sender;
        listing.depositFee = depositFee;
        listing.fixedFee = fixedFee;
        listing.usageFee = usageFee;
        listing.inUse = false;
        listing.borrower = address(0);
        listing.borrowTime = 0;
        listing.lastClaim = 0;

        emit NftListed(nftAddress, tokenId, msg.sender);
    }

    function delist(address nftAddress, uint tokenId) external {
        require(
            IERC721A(nftAddress).ownerOf(tokenId) == address(this),
            "The NFT is not owned by the NFTry address"
        );

        Listing storage listing = listings[nftAddress][tokenId];
        require(!listing.inUse, "The NFT is already borrowed");
        require(listing.owner == msg.sender, "Only owner can delist");

        IERC721A(nftAddress).transferFrom(address(this), msg.sender, tokenId);

        // reset listings
        listing.owner = address(0);
        listing.depositFee = 0;
        listing.fixedFee = 0;
        listing.usageFee = 0;
        listing.inUse = false;
        listing.borrower = address(0);
        listing.borrowTime = 0;
        listing.lastClaim = 0;

        // claim 안해간 fee 는 환불 X

        emit NftDelisted(nftAddress, tokenId, msg.sender);
    }

    function claimFixedFee(address nftAddress, uint tokenId) external {
        Listing storage listing = listings[nftAddress][tokenId];
        require(listing.owner == msg.sender, "Only Owner can claim");

        uint fixedfees = fixedFees[nftAddress][tokenId];
        require(fixedfees > 0, "Fixed Fees is 0");

        ERC20(paymentToken).transfer(msg.sender, fixedfees);
        fixedFees[nftAddress][tokenId] = 0;
        emit FixedFeeClaimed(nftAddress, tokenId, msg.sender, fixedfees);
    }

    function claimUsageFee(address nftAddress, uint tokenId) external {
        Listing storage listing = listings[nftAddress][tokenId];
        require(listing.owner == msg.sender, "Only Owner can claim");

        uint elapsedHours = (block.timestamp - listing.lastClaim) / 1 hours;
        uint totalUsageFees = elapsedHours * listing.usageFee;

        totalUsageFees = totalUsageFees > listing.depositFee - listing.fixedFee
            ? listing.depositFee - listing.fixedFee
            : totalUsageFees;

        ERC20(paymentToken).transfer(msg.sender, totalUsageFees);

        listing.lastClaim = block.timestamp;
        emit UsageFeeClaimed(nftAddress, tokenId, msg.sender, totalUsageFees);
    }

    // =============================================================
    //                        For NFT Borrower
    // =============================================================
    function borrow(address nftAddress, uint tokenId) external {
        Listing storage listing = listings[nftAddress][tokenId];
        require(listing.owner != address(0), "The NFT is not listed");
        require(!listing.inUse, "The NFT is already borrowed");
        require(
            IERC721A(nftAddress).ownerOf(tokenId) == address(this),
            "The NFT is not owned by the NFTry address"
        );

        ERC20(paymentToken).transferFrom(
            msg.sender,
            address(this),
            listing.depositFee
        );

        IERC721A(nftAddress).transferFrom(address(this), msg.sender, tokenId);

        listing.inUse = true;
        listing.borrower = msg.sender;
        listing.borrowTime = block.timestamp;
        listing.lastClaim = listing.borrowTime;

        fixedFees[nftAddress][tokenId] =
            fixedFees[nftAddress][tokenId] +
            listing.fixedFee;

        emit NftBorrowed(nftAddress, tokenId, msg.sender);
    }

    function returnNft(address nftAddress, uint tokenId) external {
        Listing storage listing = listings[nftAddress][tokenId];

        require(listing.borrower == msg.sender, "NFT Borrower mismatch");
        require(
            IERC721A(nftAddress).ownerOf(tokenId) == msg.sender,
            "The NFT is not owned by the 'from' address"
        );

        uint elapsedHours = (block.timestamp - listing.borrowTime) / 1 hours;
        uint totalUsageFees = elapsedHours * listing.usageFee;

        uint totalFee = totalUsageFees + listing.fixedFee > listing.depositFee
            ? listing.depositFee
            : totalUsageFees + listing.fixedFee;

        uint remainDeposit = listing.depositFee - totalFee;

        ERC20(paymentToken).transfer(msg.sender, remainDeposit);

        IERC721A(nftAddress).transferFrom(msg.sender, address(this), tokenId);

        // set listings
        listing.inUse = false;
        listing.borrower = address(0);
        listing.borrowTime = 0;

        emit NftReturned(nftAddress, tokenId, msg.sender);
    }
}
