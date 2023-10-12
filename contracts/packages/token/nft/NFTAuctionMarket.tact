/*
    This file provides traits for NFT auction market which can be easily used in a permissionless and flexible manner to auction (or simply buy/sell) NFTs. 
    Sellers and bidders are able to make customized auctions and bids that allow for a holistic NFT auction/sale mechanism.

    Reference:
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-marketplace.fc)
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-sale.fc)
    [NFT Auction Template](https://github.com/avolabs-io/nft-auction)
*/
import "./NFTItem";

message SetUpAuction {
    nftAddress: Address;            // NFT address to be auctioned
    reservePrice: Int as coins;     // minimum bid price to start the auction timer
    buyNowPrice: Int as coins;      // price at which the NFT can be directly bought
    auctionPeriod: Int as uint256;  // time when the auction ends after it starts
    beneficiary: Address?;           // the address of the beneficiary
}

message ReviseSetUpAuction {
    nftAddress: Address;            // NFT address to be auctioned
    reservePrice: Int as coins;     // minimum bid price to start the auction timer
    buyNowPrice: Int as coins;      // price at which the NFT can be directly bought
    auctionPeriod: Int as uint256;  // time when the auction ends after it starts
    beneficiary: Address?;           // the address of the beneficiary
    // TODO: beneficiary: Address?;           // the address of the beneficiary
}

message ReviseAuction {
    reviseAuctionInfo: AuctionInfo;
}

message BuildNftAuction {
    auctionInfo: AuctionInfo;
}

message EndAuction {
    nftAddress: Address;    
}

// @dev This message is used to ask NFT auction market contract to transfer NFT to the new owner
message TransferNFT {
    nftAddress: Address;
    seller: Address;
    query_id: Int as uint64;            
    new_owner: Address; 
    response_destination: Address; 
    custom_payload: Cell?; 
    forward_amount: Int as coins; 
    forward_payload: Slice as remaining;  
}

// @dev This struct is used to store auction information
// @note If you want to use custom auction parameters or logic, consider overriding this struct and setUpAuction function in a derived contract
struct AuctionInfo {
    bidIncreasePercentage: Int as uint256;  // the minimum percentage by which a new bid must exceed the current highest bid
    auctionBidPeriod: Int as uint256;       // increments the length of time the auction is open in which a new bid can be made after each bid
    auctionPeriod: Int as uint256;          // the time at which the auction will end
    reservePrice: Int as coins;             // the minimum price that must be paid for the NFT
    buyNowPrice: Int as coins;              // the price that must be paid for the NFT if the buyer chooses to buy it now
    nftHighestBid: Int as coins;            // the highest bid that has been made so far
    nftHighestBidder: Address;              // the address of the bidder who has made the highest bid so far
    nftSeller: Address;                     // the address of the seller
    whitelistedBuyer: Address;              // the seller can specify a whitelisted address for a sale (this is effectively a direct sale)
    nftRecipient: Address;                  // the bidder can specify a recipient for the NFT if their bid is successful
    beneficiary: Address;                  // the address of the beneficiary
}

trait NFTAuctionMarketStandard {
    owner: Address;
    // Check whether nft is transfered to NFT Auction Market Contract
    auctionTransferCheck: map<Int, Int>; // key => hash(sellerAddress and nftAddress), vlaue => 1: set, 0: not set
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
        let ctx: Context = context();
        let prev_owner: Address = msg.prev_owner; // Seller Address
        let nftAddress: Address = ctx.sender;
        let hashSellerNftAddress: Int = self.get_hash_seller_nft_address(prev_owner, nftAddress);
        // Set nft transfer checking to 1
        self.auctionTransferCheck.set(hashSellerNftAddress, 1);
        let payload: Slice = msg.forward_payload;
        
        if(payload.empty() == false) {  
            self._parse_forward_payload(prev_owner, nftAddress, payload);
        }
    }

    // @dev Handles the receipt of a SetUpAuction message.
    //      First, it verifies if the NFT has been transferred to the NFT Auction Market Contract.
    //      Upon successful validation, it sets up the auction for the specified NFT and deploys 
    //      a new NFT Auction Contract instance for it.
    receive(msg: SetUpAuction) {
        let ctx: Context = context();
        let sellerAddress: Address = ctx.sender;
        let hashSellerNftAddress: Int = self.get_hash_seller_nft_address(sellerAddress, msg.nftAddress);
        self._auction_transfer_validate(hashSellerNftAddress);
        if(msg.beneficiary == null) {
            msg.beneficiary = sellerAddress;
        }
        // Set up auction info
        let auctionInfo: AuctionInfo = self._set_up_auction(sellerAddress, msg.nftAddress, msg.reservePrice, msg.buyNowPrice, msg.auctionPeriod, msg.beneficiary!!); // set up auction
        self._set_price_validate(msg.buyNowPrice, msg.reservePrice);
        let nftAuctionInit: StateInit = self._nft_auction_init(msg.nftAddress, sellerAddress);
        let nftAuctionAddress: Address = self.get_nft_auction_address(msg.nftAddress, sellerAddress);
        self._auction_set_validate(nftAuctionAddress);
        self.auctionOverCheck.set(nftAuctionAddress, msg.nftAddress);

        // Deploy a new NFT Auction Contract
        self._build_auction(nftAuctionAddress, auctionInfo, nftAuctionInit);
    }

    // @dev Handles the TransferNFT message and facilitates NFT transfer to the auction's winning bidder.
    receive(msg: TransferNFT) {
        let ctx: Context = context();
        let nftAuctionAddress: Address = ctx.sender;
        self._auction_not_set_validate(nftAuctionAddress);
        send(SendParameters{
            to: msg.nftAddress, 
            value: 0, 
            bounce: false,
            mode: SendRemainingValue,
            body: Transfer {
                query_id: msg.query_id,
                new_owner: msg.new_owner,
                response_destination: msg.response_destination,
                custom_payload: msg.custom_payload,
                forward_amount: msg.forward_amount,
                forward_payload: msg.forward_payload
            }.toCell()
        });
        self.auctionOverCheck.set(ctx.sender, null);
        let hashSellerNftAddress: Int = self.get_hash_seller_nft_address(msg.seller, msg.nftAddress);
        self.auctionTransferCheck.set(hashSellerNftAddress, null);
    }

    // @dev Updates auction details after verifying NFT transfer and previous auction setup, then communicates the update to the nftAuctionAddress.
    receive(msg: ReviseSetUpAuction) {
        let ctx: Context = context();
        let sellerAddress: Address = ctx.sender;
        let hashSellerNftAddress: Int = self.get_hash_seller_nft_address(sellerAddress, msg.nftAddress);
        self._auction_transfer_validate(hashSellerNftAddress);
        // Get nft auction address
        let nftAuctionAddress: Address = self.get_nft_auction_address(msg.nftAddress, sellerAddress);
        self._auction_not_set_validate(nftAuctionAddress);
        if(msg.beneficiary == null) {
            msg.beneficiary = sellerAddress;
        }
        // Set up auction info
        let auctionInfo: AuctionInfo = self._set_up_auction(sellerAddress, msg.nftAddress, msg.reservePrice, msg.buyNowPrice, msg.auctionPeriod, msg.beneficiary!!); // set up auction
        self.auctionOverCheck.set(nftAuctionAddress, msg.nftAddress);
        let newAuctionInfo: AuctionInfo = self._set_up_auction(sellerAddress, msg.nftAddress, msg.reservePrice, msg.buyNowPrice, msg.auctionPeriod, msg.beneficiary!!); // set up auction
        send(SendParameters{
                to: nftAuctionAddress,
                value: 0,
                mode: SendRemainingValue,
                bounce: false,
                body: ReviseAuction {
                    reviseAuctionInfo: newAuctionInfo
                }.toCell()
            }
        );
    }

    // @dev Allows the seller to terminate an auction. 
    //      It verifies if the auction was previously set and then sends a message to the nftAuctionAddress to conclude the auction.
    //      It will transfer the NFT to the highest bidder or back to the seller(If autcion not started).
    receive(msg: EndAuction) {
        // Seller can end auction.
        let ctx: Context = context();
        let sellerAddress: Address = ctx.sender;
        let hashSellerNftAddress: Int = self.get_hash_seller_nft_address(sellerAddress, msg.nftAddress);
        let nftAuctionAddress: Address = self.get_nft_auction_address(msg.nftAddress, sellerAddress);
        self._auction_not_set_validate(nftAuctionAddress);
        send(SendParameters{
                to: nftAuctionAddress,
                value: 0,
                mode: SendRemainingValue,
                bounce: false,
                body: "EndAuction".asComment()
            }
        );
    }

    //********************************************//
    //             Internal functions             //
    //********************************************//

    virtual inline fun _parse_forward_payload(seller: Address, nftAddress: Address, payload: Slice) {
        // Parse payload
        let beneficiary: Address = payload.loadAddress();
        let reservePrice: Int = payload.loadCoins();
        let buyNowPrice: Int = payload.loadCoins();
        let auctionPeriod: Int = payload.loadUint(256);

        // Set up auction info
        let auctionInfo: AuctionInfo = self._set_up_auction(seller, nftAddress, reservePrice, buyNowPrice, auctionPeriod, beneficiary); // set up auction
        self._set_price_validate(buyNowPrice, reservePrice);
        let nftAuctionInit: StateInit = self._nft_auction_init(nftAddress, seller);
        let nftAuctionAddress: Address = self.get_nft_auction_address(nftAddress, seller);
        self._auction_set_validate(nftAuctionAddress);
        self.auctionOverCheck.set(nftAuctionAddress, nftAddress);

        // Deploy a new NFT Auction Contract
        self._build_auction(nftAuctionAddress, auctionInfo, nftAuctionInit);
    }

    virtual inline fun _build_auction(nftAuctionAddress: Address, auctionInfo: AuctionInfo, nftAuctionInit: StateInit) {
        send(SendParameters{
                to: nftAuctionAddress,
                value: 0,
                mode: SendRemainingValue,
                bounce: false,
                body: BuildNftAuction {
                    auctionInfo: auctionInfo
                }.toCell(),
                code: nftAuctionInit.code, 
                data: nftAuctionInit.data
            }
        );
    }
    
    virtual inline fun _set_price_validate(buyNowPrice: Int, reservePrice: Int) {
        require(buyNowPrice > reservePrice, "BuyNowPrice must be greater than reservePrice.");
    }

    virtual inline fun _auction_set_validate(nftAuctionAddress: Address) {
        require(self.auctionOverCheck.get(nftAuctionAddress) == null, "Auction was already set for this NFT.");
    }

    virtual inline fun _auction_not_set_validate(nftAuctionAddress: Address) {
        require(self.auctionOverCheck.get(nftAuctionAddress) != null, "Auction was not set before.");
    }

    virtual inline fun _auction_transfer_validate(hashSellerNftAddress: Int) {
        require(self.get_is_auction_transfer_check(hashSellerNftAddress) == 1, "This NFT didn't transfer to NFT Auction Market Contract yet.");
    }

    // @dev Initializes an auction for a specified NFT with given parameters such as reserve price, buy now price, and auction duration.
    // @note If you want to use custom auction parameters or logic, consider overriding this function and AuctionInfo struct in a derived contract.
    virtual inline fun _set_up_auction(sellerAddress: Address, nftAddress: Address, reservePrice: Int, buyNowPrice: Int, auctionPeriod: Int, beneficiary: Address): AuctionInfo {
        let hashSellerNftAddress: Int = self.get_hash_seller_nft_address(sellerAddress, nftAddress);
        return AuctionInfo {
            bidIncreasePercentage: self.defaultBidIncreasePercentage,
            auctionBidPeriod: self.defaultAuctionBidPeriod,
            auctionPeriod: auctionPeriod,
            reservePrice: reservePrice,
            buyNowPrice: buyNowPrice,
            nftHighestBid: 0,
            nftHighestBidder: sellerAddress,
            nftSeller: sellerAddress,
            whitelistedBuyer: sellerAddress,
            nftRecipient: sellerAddress,
            beneficiary: beneficiary
        };
    }

    // @dev Retrieves the initial state for the NFT auction contract.
    // @note one MUST override this function to provide NFT Auction initCode
    abstract fun _nft_auction_init(nftAddress: Address, seller: Address): StateInit;

    //*********************************//
    //             Getters             //
    //*********************************//

    // @dev Determines the NFT auction contract address.
    get fun get_nft_auction_address(nftAddress: Address, seller: Address): Address {
        let nftAuctionInit: StateInit = self._nft_auction_init(nftAddress, seller);
        return contractAddress(nftAuctionInit);
    }

    // @dev Generates a hash value based on the seller and NFT address.
    get fun get_hash_seller_nft_address(seller: Address, nftAddress: Address): Int {
        return beginCell().storeAddress(seller).storeAddress(nftAddress).endCell().asSlice().hash();
    }

    // @dev Checks if the auction transfer for a given hash is valid.
    get fun get_is_auction_transfer_check(hashSellerNftAddress: Int): Int {
        if(self.auctionTransferCheck.get(hashSellerNftAddress) == null) {
            return 0;
        }
        else {
            return 1;
        }
    }
}