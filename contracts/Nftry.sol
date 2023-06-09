// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC721A.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NFTRY {
    address USDC = 0x9758211252cE46EEe6d9685F2402B7DdcBb2466d; // Testnet Custom USDC
    struct Listing {
        address owner;
        uint deposit;
        uint fixedFee;
        uint usageFee; // per hour
        address borrower;
        uint borrowTime;
        uint lastClaim;
        uint unclaimedFixedFees;
        uint unclaimedUsageFees;
        bool rentalStopped;
    }

    struct BorrowableNFT {
        address nftAddress;
        uint tokenId;
        uint deposit;
        uint fixedFee;
        uint usageFee;
    }

    struct BorrowedNFT {
        address nftAddress;
        uint tokenId;
        uint deposit;
        uint fixedFee;
        uint usageFee;
        address borrowedFrom;
        uint borrowedTime;
    }

    struct LentNFT {
        address nftAddress;
        uint tokenId;
        uint deposit;
        uint fixedFee;
        uint usageFee;
        address borrowedBy;
        uint borrowedTime;
    }

    // nft address & token id
    mapping(address => mapping(uint => Listing)) listings;

    // nft address
    mapping(address => uint[]) public allTokens;

    // lender's address -> token ID[]
    mapping(address => uint[]) public allLenders;
    // lender's address & token ID -> nft address
    mapping(address => mapping(uint => address)) public lenderToNftAddress;

    // borrower's address -> token ID[]
    mapping(address => uint[]) public allBorrowers;
    // borrower's address & token ID -> nft address
    mapping(address => mapping(uint => address)) public borrowerToNftAddress;

    event NftListed(
        address indexed nftAddress,
        uint indexed tokenId,
        address owner
    );

    event NftDelisted(
        address indexed nftAddress,
        uint indexed tokenId,
        address owner
    );

    event NftLiquidated(
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

    // =============================================================
    //                        For NFT Lender
    // =============================================================
    function list(
        address nftAddress,
        uint tokenId,
        uint deposit,
        uint fixedFee,
        uint usageFee
    ) external {
        require(
            IERC721A(nftAddress).ownerOf(tokenId) == msg.sender,
            "The NFT is not owned by the 'from' address"
        );

        IERC721A(nftAddress).transferFrom(msg.sender, address(this), tokenId);
        Listing storage listing = listings[nftAddress][tokenId];
        _resetListing(listing);
        listing.owner = msg.sender;
        listing.deposit = deposit;
        listing.fixedFee = fixedFee;
        listing.usageFee = usageFee;

        allTokens[nftAddress].push(tokenId);

        allLenders[msg.sender].push(tokenId);
        lenderToNftAddress[msg.sender][tokenId] = nftAddress;

        emit NftListed(nftAddress, tokenId, msg.sender);
    }

    function delist(address nftAddress, uint tokenId) external {
        require(
            IERC721A(nftAddress).ownerOf(tokenId) == address(this),
            "The NFT is not owned by the NFTRY address"
        );

        Listing storage listing = listings[nftAddress][tokenId];
        require(listing.borrower == address(0), "The NFT is already borrowed");
        require(listing.owner == msg.sender, "Only owner can delist");

        IERC721A(nftAddress).transferFrom(address(this), msg.sender, tokenId);

        claim(nftAddress, tokenId);

        _resetListing(listing);

        // Remove the tokenId from the lender's list.
        uint[] storage lenderTokens = allLenders[msg.sender];
        for (uint i = 0; i < lenderTokens.length; i++) {
            if (lenderTokens[i] == tokenId) {
                lenderTokens[i] = lenderTokens[lenderTokens.length - 1];
                lenderTokens.pop();
                break;
            }
        }

        delete lenderToNftAddress[msg.sender][tokenId];

        emit NftDelisted(nftAddress, tokenId, msg.sender);
    }

    function _resetListing(Listing storage listing) internal {
        listing.owner = address(0);
        listing.deposit = 0;
        listing.fixedFee = 0;
        listing.usageFee = 0;
        listing.borrower = address(0);
        listing.borrowTime = 0;
        listing.lastClaim = 0;
        listing.unclaimedFixedFees = 0;
        listing.unclaimedUsageFees = 0;
        listing.rentalStopped = false;
    }

    function claim(address nftAddress, uint tokenId) public {
        Listing storage listing = listings[nftAddress][tokenId];
        require(listing.owner == msg.sender, "Only Owner can claim");
        if (listing.unclaimedFixedFees > 0) _claimFixedFee(nftAddress, tokenId);
        _claimUsageFee(nftAddress, tokenId);
    }

    function _claimFixedFee(address nftAddress, uint tokenId) internal {
        Listing storage listing = listings[nftAddress][tokenId];
        ERC20(USDC).transfer(msg.sender, listing.unclaimedFixedFees);
        emit FixedFeeClaimed(
            nftAddress,
            tokenId,
            msg.sender,
            listing.unclaimedFixedFees
        );
        listing.unclaimedFixedFees = 0;
    }

    function _claimUsageFee(address nftAddress, uint tokenId) internal {
        Listing storage listing = listings[nftAddress][tokenId];
        if (listing.borrower != address(0)) {
            uint unclaimedUsageFees = ((block.timestamp - listing.lastClaim) *
                listing.usageFee) / 1 hours;

            uint claimedUsageFees = ((listing.lastClaim - listing.borrowTime) *
                listing.usageFee) / 1 hours;

            uint maximalUsageFees = listing.deposit - listing.fixedFee;

            if (maximalUsageFees > unclaimedUsageFees + claimedUsageFees) {
                listing.unclaimedUsageFees += unclaimedUsageFees;
                listing.lastClaim = block.timestamp;
            } else {
                // Liquidation
                listing.unclaimedUsageFees +=
                    listing.deposit -
                    listing.fixedFee -
                    claimedUsageFees;
                emit NftLiquidated(nftAddress, tokenId, listing.owner);
                // TODO : liquidation ; force to delist the NFT from NFTRY
            }
        }

        if (listing.unclaimedUsageFees > 0) {
            ERC20(USDC).transfer(msg.sender, listing.unclaimedUsageFees);
            listing.unclaimedUsageFees = 0;
            emit UsageFeeClaimed(
                nftAddress,
                tokenId,
                msg.sender,
                listing.unclaimedUsageFees
            );
        }
    }

    function stopOrResumeLending(address nftAddress, uint tokenId) external {
        Listing storage listing = listings[nftAddress][tokenId];
        require(
            listing.owner == msg.sender,
            "Only Owner can stop/resume lending"
        );
        listing.rentalStopped = !listing.rentalStopped;
    }

    // =============================================================
    //                        For NFT Borrower
    // =============================================================
    function borrow(address nftAddress, uint tokenId) external {
        Listing storage listing = listings[nftAddress][tokenId];
        require(listing.owner != address(0), "The NFT is not listed");
        require(listing.borrower == address(0), "The NFT is already borrowed");
        require(
            IERC721A(nftAddress).ownerOf(tokenId) == address(this),
            "The NFT is not owned by the NFTRY address"
        );
        require(!listing.rentalStopped, "The NFT is stopped to rent");

        ERC20(USDC).transferFrom(msg.sender, address(this), listing.deposit);

        IERC721A(nftAddress).transferFrom(address(this), msg.sender, tokenId);

        listing.borrower = msg.sender;
        listing.borrowTime = block.timestamp;
        listing.lastClaim = listing.borrowTime;
        listing.unclaimedFixedFees += listing.fixedFee;

        allBorrowers[msg.sender].push(tokenId);
        borrowerToNftAddress[msg.sender][tokenId] = nftAddress;

        emit NftBorrowed(nftAddress, tokenId, msg.sender);
    }

    function returnNft(address nftAddress, uint tokenId) external {
        Listing storage listing = listings[nftAddress][tokenId];

        require(listing.borrower == msg.sender, "NFT Borrower mismatch");
        require(
            IERC721A(nftAddress).ownerOf(tokenId) == msg.sender,
            "The NFT is not owned by the 'from' address"
        );

        uint totalUsageFees = ((block.timestamp - listing.borrowTime) *
            listing.usageFee) / 1 hours;

        require(
            totalUsageFees + listing.fixedFee <= listing.deposit,
            "You've used up your deposit so you can't return the NFT"
        );

        uint claimedUsageFee = ((listing.lastClaim - listing.borrowTime) *
            listing.usageFee) / 1 hours;

        listing.unclaimedUsageFees += totalUsageFees - claimedUsageFee;

        ERC20(USDC).transfer(
            msg.sender,
            listing.deposit - listing.fixedFee - totalUsageFees
        );

        IERC721A(nftAddress).transferFrom(msg.sender, address(this), tokenId);

        listing.borrower = address(0);
        listing.borrowTime = 0;
        listing.lastClaim = 0;

        uint[] storage borrowerTokens = allBorrowers[msg.sender];
        for (uint i = 0; i < borrowerTokens.length; i++) {
            if (borrowerTokens[i] == tokenId) {
                borrowerTokens[i] = borrowerTokens[borrowerTokens.length - 1];
                borrowerTokens.pop();
                break;
            }
        }

        delete borrowerToNftAddress[msg.sender][tokenId];

        emit NftReturned(nftAddress, tokenId, msg.sender);
    }

    // =============================================================
    //                        View Functions
    // =============================================================
    function getAllBorrowableNFTListByContractAddress(
        address nftAddress
    ) public view returns (BorrowableNFT[] memory) {
        BorrowableNFT[] memory borrowableNFTs = new BorrowableNFT[](
            allTokens[nftAddress].length
        );
        uint count = 0;
        for (uint i = 0; i < allTokens[nftAddress].length; i++) {
            uint tokenId = allTokens[nftAddress][i];
            if (listings[nftAddress][tokenId].borrower == address(0)) {
                borrowableNFTs[count] = BorrowableNFT(
                    nftAddress,
                    tokenId,
                    listings[nftAddress][tokenId].deposit,
                    listings[nftAddress][tokenId].fixedFee,
                    listings[nftAddress][tokenId].usageFee
                );
                count++;
            }
        }

        // to fit the count
        BorrowableNFT[] memory result = new BorrowableNFT[](count);
        for (uint i = 0; i < count; i++) {
            result[i] = borrowableNFTs[i];
        }
        return result;
    }

    function getAllBorrowedNFTListByWalletAddress(
        address borrower
    ) public view returns (BorrowedNFT[] memory) {
        BorrowedNFT[] memory borrowedNFTs = new BorrowedNFT[](
            allBorrowers[borrower].length
        );
        uint count = 0;
        for (uint i = 0; i < allBorrowers[borrower].length; i++) {
            uint tokenId = allBorrowers[borrower][i];
            address nftAddress = borrowerToNftAddress[borrower][tokenId];
            Listing memory listing = listings[nftAddress][tokenId];
            if (
                listing.borrower != address(0) && listing.borrower == borrower
            ) {
                borrowedNFTs[count] = BorrowedNFT(
                    nftAddress,
                    tokenId,
                    listing.deposit,
                    listing.fixedFee,
                    listing.usageFee,
                    listing.owner,
                    listing.borrowTime
                );
                count++;
            }
        }
        // to fit the count
        BorrowedNFT[] memory result = new BorrowedNFT[](count);
        for (uint i = 0; i < count; i++) {
            result[i] = borrowedNFTs[i];
        }
        return result;
    }

    function getAllLentNFTListByWalletAddress(
        address lender
    ) public view returns (LentNFT[] memory) {
        LentNFT[] memory lentNFTs = new LentNFT[](allLenders[lender].length);
        uint count = 0;
        for (uint i = 0; i < allLenders[lender].length; i++) {
            uint tokenId = allLenders[lender][i];
            address nftAddress = lenderToNftAddress[lender][tokenId];
            Listing memory listing = listings[nftAddress][tokenId];
            if (listing.borrower != address(0) && listing.owner == lender) {
                lentNFTs[count] = LentNFT(
                    nftAddress,
                    tokenId,
                    listing.deposit,
                    listing.fixedFee,
                    listing.usageFee,
                    listing.borrower,
                    listing.borrowTime
                );
                count++;
            }
        }
        // Trim the array to fit the count
        LentNFT[] memory result = new LentNFT[](count);
        for (uint i = 0; i < count; i++) {
            result[i] = lentNFTs[i];
        }
        return result;
    }
}
