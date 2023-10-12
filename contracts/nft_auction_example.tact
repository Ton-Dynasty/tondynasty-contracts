import "@stdlib/deploy";
import "./packages/token/nft/NFTAuctionMarket";
import "./packages/token/nft/NFTAuction";
contract ExampleNFTAuctionMarket with Deployable, NFTAuctionMarketStandard {
    owner: Address;
    // Get auction info by seller address and nft address.
    nftContractAuctions: map<Int, AuctionInfo>; // key => hash(sellerAddress and nftAddress), value => AuctionInfo
    // Check whether nft is transfered to NFT Auction Market Contract
    auctionTransferCheck: map<Int, Int>; // key => hash(sellerAddress and nftAddress), vlaue => 1: set, 0: not set
    // Get auction info by nft collection address and nft id.
    collectionNftIdToAuction: map<Int, Int>; // key => hash(nft collection address and nft id), value => hash(sellerAddress and nftAddress)
    // Check whether nft auction is over or not
    auctionOverCheck: map<Address, Address>;  // key => nft auction contract address, value => 1: not over, 0: over
    init(owner: Address) {
        self.owner = owner;
    }

    // @dev Retrieves the initial state for the NFT auction contract.
    override get fun _nft_auction_init(nftAddress: Address, seller: Address): StateInit {
        return initOf ExampleNFTAuction(myAddress(), nftAddress, seller);
    }
}

contract ExampleNFTAuction with NFTAuctionStandard {
    owner: Address;
    nftAddress: Address;
    seller: Address;
    auctionInfo: AuctionInfo;
    auctionBidPeriod: Int;
    isInitialized: Int;
    auctionEndTime: Int;

    init(owner: Address, nftAddress: Address, seller: Address) {
        self.owner = owner;
        self.nftAddress = nftAddress;
        self.seller = seller;
        //self.auctionInfo = auctionInfo;
        self.auctionBidPeriod = 0;
        self.auctionEndTime = 0;
        self.isInitialized = 0;
        self.auctionInfo = AuctionInfo {
            bidIncreasePercentage: 0,
            auctionBidPeriod: 0,
            auctionPeriod: 0,
            reservePrice: 0,
            buyNowPrice: 0,
            nftHighestBid: 0,
            nftHighestBidder: newAddress(0, 0),
            nftSeller: seller,
            whitelistedBuyer: seller,
            nftRecipient: seller,
            beneficiary: seller
        };
    }
}
