/*
    This file provides traits for NFT auction market which can be easily used in a permissionless and flexible manner to auction (or simply buy/sell) NFTs. 
    Sellers and bidders are able to make customized auctions and bids that allow for a holistic NFT auction/sale mechanism.

    Reference:
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-marketplace.fc)
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-sale.fc)
    [NFT Auction Template](https://github.com/avolabs-io/nft-auction)
*/

message SetUpAuction {
    nftAddress: Address;        // NFT address to be auctioned
    reservePrice: Int as coins; // minimum bid price to start the auction timer
    buyNowPrice: Int as coins;  // price at which the NFT can be directly bought
    auctionPeriod: Int;         // duration for others to counter-bid after the highest bid is placed
}

// @dev This struct is used to store auction information
// @note If you want to use custom auction parameters or logic, consider overriding this struct, setUpAuction function in a derived contract and the same struct in NFT auction contract.
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

message OwnershipAssigned {
    query_id: Int as uint64;
    prev_owner: Address;
    forward_payload: Cell?; 
}

// @dev This message is used to ask NFT auction market contract to transfer NFT to the new owner
message TransferNFT {
    nftAddress: Address;
    seller: Address;
    query_id: Int as uint64;            
    new_owner: Address; 
    response_destination: Address?; 
    custom_payload: Cell?; 
    forward_amount: Int as coins; 
    forward_payload: Cell?; 
}

trait NFTAuctionMarketStandard {
    owner: Address;
    // Get auction info by seller address and nft address.
    nftContractAuctions: map<Int, AuctionInfo>; // key => hash(sellerAddress and nftAddress), value => AuctionInfo
    // Check whether nft is transfered to NFT Auction Market Contract
    auctionTransferCheck: map<Int, Int>; // key => hash(sellerAddress and nftAddress), vlaue => 1: set, 0: not set
    // Get auction info by nft collection address and nft id.
    collectionNftIdToAuction: map<Int, Int>; // key => hash(nft collection address and nft id), value => hash(sellerAddress and nftAddress)
    // Check whether nft auction is over or not
    auctionOverCheck: map<Address, Address>;  // key => nft auction contract address, value => 1: not over, 0: over

    // @dev Default parameters for setting up an NFT auction
    virtual const defaultBidIncreasePercentage: Int = 100;
    virtual const defaultAuctionBidPeriod: Int = 86400; // 1 day
    virtual const minimumSettableIncreasePercentage: Int = 100;
    virtual const maximumMinPricePercentage: Int = 8000;

    //********************************************//
    //                  Messages                  //
    //********************************************//

    // Default receive function to receive funds
    receive() {}
    
    // @dev Processes the OwnershipAssigned message and updates auction mappings,
    //      and confirms NFT transfer to the Auction Market.
    receive(msg: OwnershipAssigned) {
        let cxt: Context = context();
        let prev_owner: Address = msg.prev_owner; // Seller Address
        let nftAddress: Address = cxt.sender;
        let payload: Cell = msg.forward_payload!!;
        let parser: Slice = payload.beginParse();
        let collectionAddress: Address = parser.loadAddress();
        let nftId: Int = parser.loadInt(32);

        // Record nft collection address and nft id to auction, so that we can get auction info by nft collection address and nft id
        let collectionAndNftId: Int = beginCell().storeAddress(collectionAddress).storeInt(nftId, 32).endCell().asSlice().hash();
        let hashSellerNftAddress: Int = self.hashSellerNftAddress(prev_owner, nftAddress);
        self.collectionNftIdToAuction.set(collectionAndNftId, hashSellerNftAddress);

        // Set nft transfer checking to 1
        self.auctionTransferCheck.set(hashSellerNftAddress, 1);
    }

    // @dev Handles the receipt of a SetUpAuction message.
    //      First, it verifies if the NFT has been transferred to the NFT Auction Market Contract.
    //      Upon successful validation, it sets up the auction for the specified NFT and deploys 
    //      a new NFT Auction Contract instance for it.
    receive(msg: SetUpAuction) {
        let cxt: Context = context();
        let sellerAddress: Address = cxt.sender;
        let hashSellerNftAddress: Int = self.hashSellerNftAddress(sellerAddress, msg.nftAddress);
        if(self.isAuctionTransferCheck(hashSellerNftAddress) != 1) {
            throw(1003); // This NFT didn't transfer to NFT Auction Market Contract yet.
        }
        self.setUpAuction(sellerAddress, msg.nftAddress, msg.reservePrice, msg.buyNowPrice, msg.auctionPeriod); // set up auction
        // Deploy a new NFT Auction Contract
        let auctininfo: AuctionInfo = self.nftContractAuctions.get(hashSellerNftAddress)!!;
        let nftAuctionInit: StateInit = self.nftAuctionInit(msg.nftAddress, auctininfo);
        let nftAuctionAddress: Address = self.nftAuctionAddress(msg.nftAddress, auctininfo);
        if(self.auctionOverCheck.get(nftAuctionAddress) != null) {
            throw(1008); // Auction was already set for this NFT.
        }
        self.auctionOverCheck.set(nftAuctionAddress, msg.nftAddress);
        send(SendParameters{
                to: nftAuctionAddress,
                value: 0,
                mode: SendRemainingValue,
                bounce: false,
                body: "BuildNftAuction".asComment(),
                code: nftAuctionInit.code, 
                data: nftAuctionInit.data
            }
        );
    }

    // @dev Handles the TransferNFT message and facilitates NFT transfer to the auction's winning bidder.
    receive(msg: TransferNFT) {
        let cxt: Context = context();
        if(self.auctionOverCheck.get(cxt.sender) == null) {
            throw(1002); // Auction was not set before
        }
        send(SendParameters{
            to: msg.nftAddress, 
            value: ton("0.05"), 
            bounce: false,
            mode: SendPayGasSeparately,
            body: Transfer {
                query_id: msg.query_id,
                new_owner: msg.new_owner,
                response_destination: msg.response_destination,
                custom_payload: msg.custom_payload,
                forward_amount: msg.forward_amount,
                forward_payload: msg.forward_payload
            }.toCell()
        });
        self.auctionOverCheck.set(cxt.sender, null);
        let hashSellerNftAddress: Int = self.hashSellerNftAddress(msg.seller, msg.nftAddress);
        self.auctionTransferCheck.set(hashSellerNftAddress, null);
    }

    receive("SetUpAgain") {
        // TODO: Let seller can update auction info.
    }

    receive("EndAuction") {
        // TODO: Let seller can end auction.
    }

    //********************************************//
    //             Internal functions             //
    //********************************************//

    // @dev Initializes an auction for a specified NFT with given parameters such as reserve price, buy now price, and auction duration.
    // @note If you want to use custom auction parameters or logic, consider overriding this function and AuctionInfo struct in a derived contract.
    virtual inline fun setUpAuction(sellerAddress: Address, nftAddress: Address, reservePrice: Int, buyNowPrice: Int, auctionPeriod: Int) {
        let hashSellerNftAddress: Int = self.hashSellerNftAddress(sellerAddress, nftAddress);
        self.nftContractAuctions.set(hashSellerNftAddress,
            AuctionInfo {
                bidIncreasePercentage: self.defaultBidIncreasePercentage,
                auctionBidPeriod: self.defaultAuctionBidPeriod,
                auctionPeriod: auctionPeriod,
                reservePrice: reservePrice,
                buyNowPrice: buyNowPrice,
                nftHighestBid: 0,
                nftHighestBidder: sellerAddress,
                nftSeller: sellerAddress,
                whitelistedBuyer: sellerAddress,
                nftRecipient: sellerAddress
            }
        );
    }

    //*********************************//
    //             Getters             //
    //*********************************//

    // @dev Retrieves the initial state for the NFT auction contract.
    get fun nftAuctionInit(nftAddress: Address, auctionInfo: AuctionInfo): StateInit {
        return initOf NftAuction(myAddress(), nftAddress, auctionInfo);
    }

    // @dev Determines the NFT auction contract address.
    get fun nftAuctionAddress(nftAddress: Address, auctionInfo: AuctionInfo): Address {
        let nftAuctionInit: StateInit = self.nftAuctionInit(nftAddress, auctionInfo);
        return contractAddress(nftAuctionInit);
    }

    // @dev Generates a hash value based on the seller and NFT address.
    get fun hashSellerNftAddress(seller: Address, nftAddress: Address): Int {
        return beginCell().storeAddress(seller).storeAddress(nftAddress).endCell().asSlice().hash();
    }

    // @dev Checks if the auction transfer for a given hash is valid.
    get fun isAuctionTransferCheck(hashSellerNftAddress: Int): Int {
        if(self.auctionTransferCheck.get(hashSellerNftAddress) == null) {
            return 0;
        }
        else {
            return 1;
        }
    }

    // @dev Fetches the auction information using the seller and NFT address.
    get fun auctionInfo(seller: Address, nftAddress: Address): AuctionInfo {
        let hashSellerNftAddress: Int = self.hashSellerNftAddress(seller, nftAddress);
        return self.nftContractAuctions.get(hashSellerNftAddress)!!;
    }
}