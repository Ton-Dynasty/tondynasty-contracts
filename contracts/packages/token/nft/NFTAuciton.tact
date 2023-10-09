/*
    This file provides traits for the NFT Auction contract, allowing users to bid on NFTs. 
    When the auction ends, the NFT goes to the highest bidder and the seller receives the bid amount. 

    Reference:
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-marketplace.fc)
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-sale.fc)
    [NFT Auction Template](https://github.com/avolabs-io/nft-auction)
*/

// @dev This struct is used to store auction information
// @note If you want to use custom auction parameters or logic, consider overriding this struct and the same struct in NFT market auction contract.
struct AuctionInfo {
    bidIncreasePercentage: Int; // the minimum percentage by which a new bid must exceed the current highest bid
    auctionBidPeriod: Int;      // increments the length of time the auction is open in which a new bid can be made after each bid
    auctionPeriod: Int;         // the time at which the auction will end
    reservePrice: Int as coins; // the minimum price that must be paid for the NFT
    buyNowPrice: Int as coins;  // the price that must be paid for the NFT if the buyer chooses to buy it now
    nftHighestBid: Int as coins;// the highest bid that has been made so far
    nftHighestBidder: Address;  // the address of the bidder who has made the highest bid so far
    nftSeller: Address;         // the address of the seller
    whitelistedBuyer: Address;  // the seller can specify a whitelisted address for a sale (this is effectively a direct sale)
    nftRecipient: Address;      // the bidder can specify a recipient for the NFT if their bid is successful
}

trait NFTAuctionStandard {
    virtual const minTonsForStorage: Int = ton("0.03");
    virtual const gasConsumption: Int = ton("0.03");

    const  auctionEnd: Internal = 0;
    const isInitialized: Int = 0;

    owner: Address;
    nftAddress: Address;
    auctionInfo: AuctionInfo;

    //********************************************//
    //                  Messages                  //
    //********************************************//

    // @dev Default receive function to receive funds
    receive() {}

    // @dev Initializes the auction when called by the owner
    receive("BuildNftAuction") {
        let cxt: Context = context();
        if(cxt.sender != self.owner) {
            throw(1001); // Only owner can build nft auction contract
        }
        if(self.isInitialized != 0) {
            throw(1004); // Contract is already initialized
        }
        self.isInitialized = 1;
        self.auctionEnd = 0;
    }

    // @dev Accepts bids for the NFT as long as the auction is active
    receive("Bid") {
        // Check if auction is still active.
        if(now() > self.auctionEnd && self.auctionEnd != 0) {
            throw(1005); // Auction ended.
        }

        let cxt: Context = context();
        let buyer: Address = cxt.sender;
        if(buyer == self.auctionInfo.nftSeller) {
            throw(1006); //NFT Seller cannot bid.
        }
        let bidValue: Int = cxt.value;
        let buyNowPrice: Int = self.auctionInfo.buyNowPrice;
        if(bidValue >= buyNowPrice) {
            self.auctionInfo.nftHighestBid = bidValue;
            // Pay winning bid amount to seller.
            self.sendWinningBidAmount();
            // Transfer NFT to buyer
            self.transferNFT(buyer);
            self.isInitialized = 0;
            return;
        }

        let bidIncreaseAmount: Int = (self.auctionInfo.nftHighestBid * (10000 + self.auctionInfo.bidIncreasePercentage)) / 10000;
        if(bidValue <= bidIncreaseAmount) {
            throw(1007); // Bid doesn't meet the minimum increase requirement.
        }
        // Send back previous highest bid to previous highest bidder.
        let prevNftHighestBidder: Address = self.auctionInfo.nftHighestBidder;
        let prevNftHighestBid: Int = self.auctionInfo.nftHighestBid;
        let paybackTon: Int = max(prevNftHighestBid - minTonsForStorage - gasConsumption,0);
        send(SendParameters{
            to: prevNftHighestBidder,
            value: paybackTon, 
            mode: SendPayGasSeparately, 
            bounce: true,
            body: "Pay bid money back to the prevNftHighestBidder".asComment()
        });
        // Update highest bid and Transfer ton back to previous highest bidder.
        self.auctionInfo.nftHighestBidder = cxt.sender;
        self.auctionInfo.nftHighestBid = bidValue;
        // If bid value is greater than reserve price, then the auction is being started.
        if (bidValue > self.auctionInfo.reservePrice) {
            self.updateAuctionEnd();
        }
    }

    // @dev Settles the auction, transferring the NFT to the highest bidder and the funds to the seller
    receive("settleAuction") {
        if(now() < self.auctionEnd) {
            throw(1000); // Auction not yet ended.
        }
        // Pay winning bid amount to seller.
        self.sendWinningBidAmount();

        // Transfer NFT to buyer
        let buyer: Address = self.auctionInfo.nftHighestBidder;
        self.transferNFT(buyer);
        self.isInitialized = 0;
    }

    //********************************************//
    //             Internal functions             //
    //********************************************//

    // @dev Updates the auction end time based on the latest bid and the defined auction bid period
    virtual inline fun updateAuctionEnd() {
        self.auctionEnd = now() + self.auctionInfo.auctionPeriod;
    }

    // @dev Transfer the NFT to the highest bidder
    // @note If you want change msg value, you should make sure that is enough for NFT Auction market contract to transfer NFT.
    virtual inline fun transferNFT(buyer: Address) {
        send(SendParameters{
            to: self.owner, 
            value: ton("0.06"), 
            bounce: false,
            mode: SendPayGasSeparately,
            body: TransferNFT {
                nftAddress: self.nftAddress,
                seller: self.auctionInfo.nftSeller,
                query_id: 0,
                new_owner: buyer,
                response_destination: buyer,
                custom_payload: emptyCell(),
                forward_amount: 0,
                forward_payload: emptyCell()
            }.toCell()
        });
    }

    // @dev Transfers the highest bid amount to the seller
    virtual inline fun sendWinningBidAmount() {
        let seller: Address = self.auctionInfo.nftSeller;
        let winningBidAmount: Int = self.auctionInfo.nftHighestBid;
        send(SendParameters{
            to: seller,
            value: winningBidAmount, 
            mode: SendPayGasSeparately, 
            bounce: true,
            body: "Pay winning bid amount".asComment()
        });
    }

    // @dev Initializes the auction end time to 0, allowing the seller to auction the NFT again in the future
    virtual inline fun initAuctionEnd() {
        let cxt: Context = context();
        if(cxt.sender != self.owner) {
            throw(1001); // Only owner can init auction end time.
        }
        self.auctionEnd = 0;
    }

    //*********************************//
    //             Getters             //
    //*********************************//

    // @dev Returns the current auction information
    get fun auctininfo(): AuctionInfo {
        return self.auctionInfo;
    }

    // @dev Checks if the auction is initialized and returns the state (1 for initialized, 0 otherwise)
    get fun isInitialized(): Int {
        return self.isInitialized;
    }

    // @dev Returns the end time of the auction
    get fun auctionEnd(): Int {
        return self.auctionEnd;
    }
}