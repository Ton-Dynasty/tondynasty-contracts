/*
    This file provides traits for the NFT Auction contract, allowing users to bid on NFTs. 
    When the auction ends, the NFT goes to the highest bidder and the seller receives the bid amount. 

    Reference:
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-marketplace.fc)
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-sale.fc)
    [NFT Auction Template](https://github.com/avolabs-io/nft-auction)
*/

trait NFTAuctionStandard {
    virtual const minTonsForStorage: Int = ton("0.03");
    virtual const gasConsumption: Int = ton("0.03");

    owner: Address;
    nftAddress: Address;
    seller: Address;
    auctionInfo: AuctionInfo;
    auctionBidPeriod: Int;
    isInitialized: Int;
    auctionEndTime: Int;

    //********************************************//
    //                  Messages                  //
    //********************************************//

    // @dev Default receive function to receive funds
    receive() {}

    // @dev Initializes the auction when called by the owner
    receive(msg: BuildNftAuction) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Only owner can build nft auction contract");
        require(self.isInitialized == 0, "Contract is already initialized");
        require(msg.auctionInfo.buyNowPrice > msg.auctionInfo.reservePrice, "BuyNowPrice must be greater than reservePrice");
        self.auctionInfo = msg.auctionInfo;
        self.isInitialized = 1;
        self.auctionBidPeriod = 0;
        self.auctionEndTime = 0;
    }

    // @dev Accepts bids for the NFT as long as the auction is active
    receive("Bid") {
        // Check if auction is still active.
        require(now() < self.auctionEndTime || self.auctionEndTime == 0, "Auction ended");
        require(self.isInitialized == 1, "Contract is not initialized");
        require(now() < self.auctionBidPeriod | self.auctionBidPeriod ==0, "Auction bid period ended");

        let ctx: Context = context();
        let buyer: Address = ctx.sender;
        require(buyer != self.auctionInfo.nftSeller, "NFT Seller cannot bid");
        let bidValue: Int = ctx.value;
        let buyNowPrice: Int = self.auctionInfo.buyNowPrice;
        if(bidValue >= buyNowPrice) {
            self.auctionInfo.nftHighestBid = bidValue;
            // Pay winning bid amount to seller.
            self._send_winning_bid_amount();
            // Transfer NFT to buyer
            self._transfer_nft(buyer);
            self.isInitialized = 0;
            return;
        }

        let bidIncreaseAmount: Int = (self.auctionInfo.nftHighestBid * (10000 + self.auctionInfo.bidIncreasePercentage)) / 10000;
        require(bidValue > bidIncreaseAmount, "Bid doesn't meet the minimum increase requirement");
        // Send back previous highest bid to previous highest bidder.
        let prevNftHighestBidder: Address = self.auctionInfo.nftHighestBidder;
        let prevNftHighestBid: Int = self.auctionInfo.nftHighestBid;
        let paybackTon: Int = max(prevNftHighestBid - self.minTonsForStorage - self.gasConsumption,0);
        send(SendParameters{
            to: prevNftHighestBidder,
            value: paybackTon, 
            mode: SendPayGasSeparately, 
            bounce: false,
            body: "Pay bid money back to the prevNftHighestBidder".asComment()
        });
        // Update highest bid and Transfer ton back to previous highest bidder.
        self.auctionInfo.nftHighestBidder = ctx.sender;
        self.auctionInfo.nftHighestBid = bidValue;
        // If bid value is greater than reserve price, then the auction is being started.
        if(bidValue > self.auctionInfo.reservePrice) {
            self._update_auction_bid_period();
            if(self.auctionEndTime == 0) { 
                // If the auction start, then set the auction end time.
                self._update_auction_end_time();
            }
        }
    }

    // @dev Settles the auction, transferring the NFT to the highest bidder and the funds to the seller
    receive("settleAuction") {
        require(now() >= self.auctionBidPeriod, "Auction not yet ended");
        // Pay winning bid amount to seller.
        self._send_winning_bid_amount();

        // Transfer NFT to buyer
        let buyer: Address = self.auctionInfo.nftHighestBidder;
        self._transfer_nft(buyer);
        self.isInitialized = 0;
    }

    // @dev Allows owner to adjust auction's reserve or buy-now prices.
    receive(msg: ReviseAuction) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Only owner can revise auction contract");
        require(self.auctionInfo.reservePrice == msg.reviseAuctionInfo.reservePrice || msg.reviseAuctionInfo.buyNowPrice == self.auctionInfo.buyNowPrice, "Cannot update reserve price and buy now price at the same time.");

        // Update the reserve price of the auction.
        // This can only be done if no bid has been made that already exceeds the original minimum price.
        if(self.auctionEndTime == 0 && self.auctionInfo.reservePrice != msg.reviseAuctionInfo.reservePrice && msg.reviseAuctionInfo.reservePrice < self.auctionInfo.buyNowPrice) {

            self.auctionInfo.reservePrice = msg.reviseAuctionInfo.reservePrice;
            if(self.auctionInfo.nftHighestBid > self.auctionInfo.reservePrice) {
                self._update_auction_bid_period();
                self._update_auction_end_time();
            }
        }
        // Update the buy now price of the auction.
        // This can only be done if no bid has been made that already exceeds the original minimum price.
        if(self.auctionEndTime == 0 && msg.reviseAuctionInfo.buyNowPrice != self.auctionInfo.buyNowPrice && msg.reviseAuctionInfo.buyNowPrice > self.auctionInfo.reservePrice) {
            self.auctionInfo.buyNowPrice = msg.reviseAuctionInfo.buyNowPrice;
        }
    }

    // @dev Ends the auction and transfers the NFT to the highest bidder or back to the seller(If autcion not started)
    receive("EndAuction") {
        // If this auction started, it will transfer NFT to highest bidder.
        // Else, it will transfer NFT to seller.
        if(self.auctionEndTime > 0) {
            // Pay royalty to the creator of the NFT
            // TODO: Implement royalty payment
            
            // Pay winning bid amount to seller.
            self._send_winning_bid_amount();
            // Transfer NFT to buyer
            let buyer: Address = self.auctionInfo.nftHighestBidder;
            self._transfer_nft(buyer);
            self.isInitialized = 0;
        }
        else {
            // Transfer NFT to seller
            let seller: Address = self.auctionInfo.nftSeller;
            self._transfer_nft(seller);
            self.isInitialized = 0;
        }
    }

    //********************************************//
    //             Internal functions             //
    //********************************************//

    // @dev Updates the auction bid period time based on the latest bid and the defined auction bid period
    virtual inline fun _update_auction_bid_period() {
        self.auctionBidPeriod = now() + self.auctionInfo.auctionBidPeriod;
    }

    // @dev Updates the auction end time
    virtual inline fun _update_auction_end_time() {
        self.auctionEndTime = now() + self.auctionInfo.auctionPeriod;
    }

    // @dev Transfer the NFT to the highest bidder
    // @note If you want change msg value, you should make sure that is enough for NFT Auction market contract to transfer NFT.
    virtual inline fun _transfer_nft(buyer: Address) {
        send(SendParameters{
            to: self.owner, 
            value: ton("0.06"), 
            bounce: true,
            mode: SendPayGasSeparately,
            body: TransferNFT {
                nftAddress: self.nftAddress,
                seller: self.auctionInfo.nftSeller,
                query_id: 0,
                new_owner: buyer,
                response_destination: buyer,
                custom_payload: emptyCell(),
                forward_amount: 0,
                forward_payload: emptySlice()
            }.toCell()
        });
    }

    // @dev Transfers the highest bid amount to the seller
    virtual inline fun _send_winning_bid_amount() {
        let seller: Address = self.auctionInfo.beneficiary;
        let winningBidAmount: Int = self.auctionInfo.nftHighestBid;
        send(SendParameters{
            to: seller,
            value: winningBidAmount - ton("0.06"), 
            mode: SendPayGasSeparately, 
            bounce: false,
            body: "Pay winning bid amount".asComment()
        });
    }

    // @dev Initializes the auction end time to 0, allowing the seller to auction the NFT again in the future
    virtual inline fun _init_auction_end() {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Only owner can init auction end time.");
        self.auctionBidPeriod = 0;
    }

    //*********************************//
    //             Getters             //
    //*********************************//

    // @dev Returns the current auction information
    get fun get_auctin_info(): AuctionInfo {
        return self.auctionInfo;
    }

    // @dev Checks if the auction is initialized and returns the state (1 for initialized, 0 otherwise)
    get fun get_is__initialized(): Int {
        return self.isInitialized;
    }

    // @dev Returns the end time of the auction
    get fun get_auction_end(): Int {
        return self.auctionEndTime;
    }

    // @dev Retruns the auction bid period
    get fun get_auction_bid_period(): Int {
        return self.auctionBidPeriod;
    }
}