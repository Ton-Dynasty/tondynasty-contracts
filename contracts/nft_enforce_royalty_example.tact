import "@stdlib/deploy";
import "@stdlib/ownable";
import "./packages/token/nft/NFTCollection";
import "./packages/token/nft/extensions/NFTRoyalty";
import "./packages/token/nft/NFTItem";
import "./packages/token/jetton/JettonMaster";
import "./packages/token/jetton/JettonWallet";
import "./packages/utils/Estimatable";
import "./packages/utils/Lockable";
import "./packages/token/nft/NFTAuction";
import "./packages/token/nft/NFTAuctionMarket";
@name(udict_set_ref)
native udict_set_ref(dict: Cell?, key_len: Int, index: Int, value: Cell): Cell?; 

const DEFAULT_RESERVE_PRICE: Int = ton("0.01");

message FractionParams {
    author: Address;
    reserve_price: Int as coins;
    max_supply: Int as coins;
    jetton_content: Cell;
}

message(0xbaa13f5f) TryRedeem {
    sender: Address; // Request sender who sent "Redeem" message to NFT Item
}

message(0xbac2f9a4) Compose {
    new_owner: Address;
}

message IssueQuota {
    amount: Int as uint32;
    price: Int as coins;
}

message BuyQuota {
    amount: Int as uint32;
}

message IncreaseQuota {
    amount: Int as uint32;
}

message WithdrawQuotaShop{
    amount: Int as coins;
    custom_payload: Cell;
}

message TransferAuctionPayload {
    seller: Address;
}

message Trade {
    reserve_price: Int as coins;
    buynow_price: Int as coins;
    auction_period: Int as uint256; 
    beneficiary: Address?;
}

message BuyAllToken {
    reserve_price: Int as coins;
}

message FractionTrade {
    buy_out: Int as coins;
    bidder: Address;
}


contract NFTFractionWallet with JettonWallet {
    balance: Int as coins = ton("0");
    owner: Address;
    jetton_master: Address;

    init(owner: Address, jetton_master: Address) {
        self.owner = owner;
        self.jetton_master = jetton_master;
    }

    receive(msg: BuyAllToken) {
        send(SendParameters{
            to: self.jetton_master,
            value: 0,
            bounce: true,
            mode: SendRemainingValue + SendIgnoreErrors,
            body: BuyAllToken{ 
                reserve_price: msg.reserve_price
            }.toCell()
        });
    }

    override inline fun calculate_jetton_wallet_init(owner_addr: Address): StateInit {
        return initOf NFTFractionWallet(owner_addr, self.jetton_master);
    }

    override inline fun _burn_validate(ctx: Context, msg: JettonBurn) {
        require(ctx.sender == self.jetton_master, "JettonWallet: Only JettonMaster can burn tokens");
        require(msg.response_destination == self.owner, "JettonWallet: Only owner can burn tokens");
    }
}

contract NFTFraction with JettonMaster, Estimatable, Deployable {
    mintable: Bool = true;          // This contract is always mintable
    total_supply: Int as coins = 0; // Total supply of the NFT item
    owner: Address;                 // NFT Item address
    jetton_content: Cell;

    max_supply: Int as coins;       // Max supply of the NFT item

    init(reserve_price: Int, max_supply: Int, owner: Address, jetton_content: Cell) {
        self.max_supply = max_supply;
        self.owner = owner;
        self.jetton_content = jetton_content;
    }

    // @dev  When mint is bounced, the total supply should be decreased
    bounced(src: bounced<JettonInternalTransfer>) {
        self.total_supply = self.total_supply - src.amount;
    }

    receive(msg: TryRedeem) {
        require(self.total_supply == self.total_supply, "NFTFraction: Total supply is not equal to max supply");
        let ctx: Context = context();
        require(ctx.sender == self.owner, "NFTFraction: Only NFT Item contract can try to redeem");
        let walletInit: StateInit = self.calculate_jetton_wallet_init(msg.sender);
        send(SendParameters{
            to: contractAddress(walletInit),
            value: self.estimate_rest_value(ctx),
            bounce: false,
            mode: SendIgnoreErrors,
            body: JettonBurn {
                query_id: 0,        
                amount: self.total_supply,
                response_destination: msg.sender,
                custom_payload: emptyCell()
            }.toCell()
        });
    }

    override inline fun calculate_jetton_wallet_init(owner_address: Address): StateInit {
        return initOf NFTFractionWallet(owner_address, myAddress());
    }

    override inline fun _burn_notification(ctx: Context, msg: JettonBurnNotification) {
        self.total_supply = self.total_supply - msg.amount;
        let remain: Int = self.estimate_rest_value(ctx) - ctx.readForwardFee();
        send(SendParameters{
            to: self.owner,
            value: remain,
            bounce: false,
            mode: SendPayGasSeparately,
            body: Compose{
                new_owner: msg.sender
            }.toCell()
        });
        if(msg.response_destination != newAddress(0, 0)){
            send(SendParameters{
                to: msg.response_destination,
                value: 0,
                bounce: false,
                mode: SendRemainingValue + SendIgnoreErrors
            });
        }
    }

    override inline fun _mint_validate(ctx: Context, msg: JettonMint) {
        require(ctx.sender == self.owner, "JettonMaster: Sender is not a NFT Item contract");
        require(self.mintable, "JettonMaster: Jetton is not mintable");
        require(self.total_supply + msg.amount <= self.total_supply, "JettonMaster: Exceeds max supply");
    }

    override inline fun _mint(ctx: Context, msg: JettonMint) {
        // Parse royalty param from forward_payload slice in JettonMint
        require(msg.custom_payload != null, "JettonMaster: Custom payload is null");
        
        // Try to parse custom_payload as royalty_param(Slice)
        let payload: Cell = msg.custom_payload!!;
        let slice: Slice = payload.asSlice();
        let numerator: Int = slice.loadInt(16);
        let denominator: Int = slice.loadInt(16);
        let destination: Address = slice.loadAddress();

        let receiverInit: StateInit = self.calculate_jetton_wallet_init(msg.receiver);
        let authorInit: StateInit = self.calculate_jetton_wallet_init(destination);
        self.total_supply = self.total_supply + msg.amount;
        let rest_value: Int = self.estimate_rest_value(ctx);
        rest_value = rest_value - ctx.readForwardFee() - msg.forward_ton_amount;
        // To receiver's jetton wallet
        send(SendParameters{
            to: contractAddress(receiverInit),
            value: 0,
            bounce: true,
            mode: SendPayGasSeparately,
            body: JettonInternalTransfer{ 
                query_id: 0,
                amount: msg.amount,
                response_address: msg.origin,
                from: myAddress(),
                forward_ton_amount: msg.forward_ton_amount,
                forward_payload: msg.forward_payload
            }.toCell(),
            code: receiverInit.code,
            data: receiverInit.data
        });
        // To author's jetton wallet
        send(SendParameters{
            to: contractAddress(authorInit),
            value: rest_value,
            bounce: true,
            mode: SendIgnoreErrors,
            body: JettonInternalTransfer{ 
                query_id: 0,
                amount: msg.amount,
                response_address: msg.origin,
                from: myAddress(),
                forward_ton_amount: msg.forward_ton_amount,
                forward_payload: msg.forward_payload
            }.toCell(),
            code: authorInit.code,
            data: authorInit.data
        });
    }

}

contract QuotaShop with Deployable, Estimatable {
    quota_amount: Int as uint32 = 0;
    quota_price: Int as coins = 0;
    author: Address;
    balance: Int as coins = 0;
    nft_item: Address;
    init (author: Address, nft_item: Address){
        self.author = author;
        self.nft_item = nft_item;
    }

    receive (msg: IssueQuota){
        let ctx: Context = context();
        require(ctx.sender == self.author, "QuotaShop: Only author can issue quota");
        require(self.quota_amount == 0, "QuotaShop: Quota is already issued");
        self.quota_amount = msg.amount;
        self.quota_price = msg.price;
    }

    receive (msg: BuyQuota){
        let ctx: Context = context();
        require(self.quota_amount > 0, "QuotaShop: Quota is not issued");
        require(self.quota_amount >= msg.amount, "QuotaShop: Not enough quota");
        require(ctx.value >= self.quota_price * msg.amount, "QuotaShop: Not enough money");
        let remain: Int = self.estimate_rest_value(ctx) - ctx.readForwardFee();
        send(SendParameters{
            to: self.nft_item,
            value: 0,
            bounce: false,
            mode: SendPayGasSeparately,
            body: IncreaseQuota{
                amount: msg.amount
            }.toCell()
        });

        self.quota_amount = self.quota_amount - msg.amount;
        self.balance = self.balance + self.quota_price * msg.amount;

        send(SendParameters{
            to: ctx.sender,
            value: remain,
            bounce: false,
            mode: SendIgnoreErrors,
            body: "Success".asComment()
        });
    }

    receive ("Withdraw"){
        let ctx: Context = context();
        require(ctx.sender == self.author, "QuotaShop: Only author can withdraw");
        send(SendParameters{
            to: self.author,
            value: self.balance,
            bounce: true,
            mode: SendRemainingValue,
            body: WithdrawQuotaShop{
                amount: self.balance,
                custom_payload: emptyCell()
            }.toCell()
        });
        self.balance = 0;
    }

    bounced (src: bounced<WithdrawQuotaShop>){
        self.balance = self.balance + src.amount;
    }
}

contract FNFTCollection with NFTCollectionStandard, NFTRoyaltyStandard, Estimatable, Deployable {
    next_item_index: Int as uint32 = 0; // if next_item_index is not -1, means sequential minting is enabled. We want a sequential minting in this example so we set it to uint32.
    collection_content: Cell;           // collection_content may be the prefix of individual_content
    owner_address: Address;             // owner_address is the address of the owner of the collection
    royalty_params: RoyaltyParams;      // royalty_params is the params of royalty

    init(owner_address: Address, collection_content: Cell, royalty_params: RoyaltyParams) {
        self.owner_address = owner_address;
        self.collection_content = collection_content;
        self.royalty_params = royalty_params;
    }

    // @dev Mint is not the standard function of NFTCollection, so we need to define it by ourselves
    receive("Mint") {
        let ctx: Context = context();
        let nftItemInit: StateInit = self._get_nft_item_state_init(self.next_item_index);
        send(SendParameters{
                to: contractAddress(nftItemInit), 
                value: self.estimate_rest_value(ctx), 
                bounce: false,
                mode: SendIgnoreErrors,
                body: Transfer {
                    query_id: 0,
                    new_owner: ctx.sender,
                    response_destination: ctx.sender,
                    custom_payload: emptyCell(),
                    forward_amount: 0,
                    forward_payload: emptySlice()
                }.toCell(),
                code: nftItemInit.code,
                data: nftItemInit.data
            });
        self.next_item_index = self.next_item_index + 1;
    }

    inline fun get_fraction_param(index: Int): FractionParams {
        let content_cell: Cell? = null;
        let value1: Builder = beginCell();
        let value1Str: StringBuilder = beginStringFromBuilder(value1);
        value1Str.append("F-TonDynasty #");
        value1Str.append(index.toString());
        content_cell = udict_set_ref(content_cell, 256, sha256("name"), value1Str.toCell());


        let value2: Builder = beginCell();
        let value2Str: StringBuilder = beginStringFromBuilder(value2);
        value2Str.append(index.toString());
        content_cell = udict_set_ref(content_cell, 256, sha256("description"), value2Str.toCell());

        let value3: Builder = beginCell();
        let value3Str: StringBuilder = beginStringFromBuilder(value3);
        value3Str.append("F-TDT #");
        value3Str.append(index.toString());
        content_cell = udict_set_ref(content_cell, 256, sha256("symbol"), value3Str.toCell());

        let jetton_content: Builder = beginCell().storeInt(0x00, 8).storeUint(1, 1).storeRef(content_cell!!);

        return FractionParams {
            author: self.owner_address,
            reserve_price: DEFAULT_RESERVE_PRICE,
            max_supply: ton("100"),
            jetton_content: jetton_content.endCell()
        };
    }

    // @dev _get_nft_item_state_init returns the initCode of NFTItem
    override inline fun _get_nft_item_state_init(index: Int): StateInit {
        return initOf FNFTItem(myAddress(), index, self.owner_address, self.collection_content, self.get_fraction_param(index));
    }

    get fun debug_fraction_param(index: Int): FractionParams {
        return self.get_fraction_param(index);
    }
}

contract FNFTItem with NFTItemStandard, Lockable, Ownable {
    override const gasConsumption: Int = ton("0.03");
    override const minTonsForStorage: Int = ton("0.04");
    // @dev Default parameters for setting up an NFT auction
    const defaultBidIncreasePercentage: Int = 100;
    const defaultAuctionBidPeriod: Int = 86400; // 1 day
    const minimumSettableIncreasePercentage: Int = 100;
    const maximumMinPricePercentage: Int = 8000;
    const auction_period: Int = 86400 * 14; // 14 day

    collection_address: Address;
    index: Int;
    owner: Address;
    individual_content: Cell;
    is_initialized: Bool = false;
    is_locked: Bool = false;
    quota: Int as uint32 = 0;
    fraction_params: FractionParams;
    
    init(collection_address: Address, index: Int, owner: Address, individual_content: Cell, fraction_params: FractionParams) {
        self.collection_address = collection_address;
        self.index = index;
        self.owner = owner;
        self.individual_content = individual_content;
        self.fraction_params = fraction_params;
    }

    receive(msg: Compose) {
        self.ensureLocked();
        let ctx: Context = context();
        let nftFractionInit: StateInit = self.get_jetton_master_init();
        require(ctx.sender == contractAddress(nftFractionInit), "FNFTItem: Only the NFT Fraction contract can compose the NFT item");
        self.owner = msg.new_owner;
        self.unlock();
        send(SendParameters{
            to: msg.new_owner,
            value: 0,
            bounce: false,
            mode: SendRemainingValue + SendIgnoreErrors,
            body: "Success".asComment()
        });
    }

    receive(msg: IncreaseQuota) {
        let ctx: Context = context();
        require(ctx.sender == contractAddress(self.get_quotashop_init()), "FNFTItem: Only the QuotaShop contract can increase the quota");
        self.quota = self.quota + msg.amount;
    }

    receive(msg: Trade) {
        let ctx: Context = context();
        self.requireOwner();
        self.ensureUnlocked();
        self.lock();
        self._buyNowPrice_validate(msg.buynow_price);
        let nftAuctionAddress: Address = self.get_nft_auction_address(self.owner);
        let auctionInfo: AuctionInfo = self._fill_up_auction_info(self.owner, msg.reserve_price, msg.buynow_price, msg.auction_period, msg.beneficiary);
        let nftAuctionInit: StateInit = self.get_nft_auction_init(self.owner);
        self._build_auction(nftAuctionAddress, auctionInfo, nftAuctionInit);
    }

    receive(msg: FractionTrade) {
        let ctx: Context = context();
        self.requireOwner();
        self.ensureUnlocked();
        self.lock();
        let beneficiary: Address = ctx.sender; // Jetton Master
        let nftAuctionAddress: Address = self.get_nft_auction_address(msg.bidder);
        let auctionInfo: AuctionInfo = self._fill_up_auction_info(msg.bidder, msg.buy_out, 0, self.auction_period, beneficiary);
        let nftAuctionInit: StateInit = self.get_nft_auction_init(msg.bidder);
        self._build_auction(nftAuctionAddress, auctionInfo, nftAuctionInit);
    }
    

    inline fun _fill_up_auction_info(sellerAddress: Address, reservePrice: Int, buyNowPrice: Int, auctionPeriod: Int, beneficiary: Address?): AuctionInfo {
        if(beneficiary == null) {
            beneficiary = sellerAddress;
        }
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
            beneficiary: beneficiary!!
        };
    }

    inline fun _build_auction(nftAuctionAddress: Address, auctionInfo: AuctionInfo, nftAuctionInit: StateInit) {
        send(SendParameters{
            to: nftAuctionAddress,
            value: 0,
            mode: SendRemainingValue + SendIgnoreErrors,
            bounce: false,
            body: BuildNftAuction {
                auctionInfo: auctionInfo
            }.toCell(),
            code: nftAuctionInit.code, 
            data: nftAuctionInit.data
        });
    }

    inline fun _buyNowPrice_validate(buyNowPrice: Int) {
        require(buyNowPrice != 0, "NFTItemStandard: Buy now price cannot be 0");
    }

    inline fun get_quotashop_init(): StateInit {
        return initOf QuotaShop(self.fraction_params.author, myAddress());
    }
    
    inline fun get_jetton_master_init(): StateInit {
        return initOf NFTFraction(DEFAULT_RESERVE_PRICE, self.fraction_params.max_supply, myAddress(), self.fraction_params.jetton_content);
    }

    inline fun get_nft_auction_init(seller: Address): StateInit {
        return initOf NFTItemAuction(myAddress(), seller);
    }

    inline fun get_nft_auction_address(seller: Address): Address {
        let nftAuctionInit: StateInit = self.get_nft_auction_init(seller);
        return contractAddress(nftAuctionInit);
    }

    inline fun fractionalize_validate(ctx: Context) {
        self.ensureUnlocked();
    }

    inline fun fractionalize(ctx: Context) {
        self.lock();
        self.owner = newAddress(0, 0);
        let nftFractionInit: StateInit = self.get_jetton_master_init();
        send(SendParameters{
            to: contractAddress(nftFractionInit),
            value: 0,
            bounce: false,
            mode: SendRemainingValue + SendIgnoreErrors,
            body: JettonMint {
                origin: ctx.sender,
                receiver: ctx.sender, 
                amount: self.fraction_params.max_supply,
                custom_payload: emptyCell(),
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),
            code: nftFractionInit.code,
            data: nftFractionInit.data
        });
    }

    override inline fun _transfer_validate(ctx: Context, msg: Transfer, remain: Int) {
        self.ensureUnlocked();
        require(ctx.sender == self.owner || ctx.sender == self.collection_address, "FNFTItem: Only the owner or collection can transfer the NFT item");
    }

    override inline fun mint(ctx: Context, msg: Transfer) {
        require(ctx.sender == self.collection_address, "NFTItemStandard: Only the collection can initialize the NFT item");
        self.is_initialized = true;
        self.owner = msg.new_owner;
        send(SendParameters{
            to: msg.response_destination,
            value: 0,
            mode:  SendIgnoreErrors + SendRemainingValue,
            body: Excesses { query_id: msg.query_id }.toCell()
        });
    }

    inline fun loadOp (payload: Cell?): Int {
        if (payload == emptyCell()) {
            return 0;
        }
        let ps: Slice = (payload!!).asSlice();
        ps.skipBits(32);
        return ps.loadUint(32);
    }
    
    inline fun storeTransferAuctionPayload(payload: TransferAuctionPayload): Cell {
        let builder: Builder = beginCell();
        builder.storeAddress(payload.seller);
        return builder.endCell();
    }
    
    inline fun loadTransferAuctionPayload(payload: Slice): TransferAuctionPayload {
        let seller: Address = payload.loadAddress();
        return TransferAuctionPayload {
            seller: seller
        };
    }

    // @dev  transfer transfer nft with royalty enforcement
    // @note - If whitelisted or self.quota > 0 do not enforce royalty:
    //          WhiteListed:
    //              1. the sender is from author wallet address
    //              2. the sender is NFT collection contract
    //              3. TODO: the sender Fraction auction contract
    //          Logic:
    //              if not whitelisted:
    //                  a. dwindles the quota by 1 (self.transfer)
    //              send OwnershipAssigned to msg.new_owner  (if sender is Fraction auction contract, send OwnershipAssigned to auction winner)
    //              send Excesses to msg.response_destination (TODO: if sender is Fraction auction contract, send Excesses to Jetton master)
    //              
    //       - If un-whilitsted and self.quota == 0, the nft will be fractionalized (send JettonMint to NFTFraction contract):
    //              a. a part of nft fraction (jetton) will be minted to the receiver
    //              b. the remain part of nft fraction (jetton) will be minted to the author
    override inline fun transfer(ctx: Context, msg: Transfer, remain: Int) {
        let transferAuctionPayload: TransferAuctionPayload? = null;
        let op: Int = self.loadOp(msg.custom_payload);
        if (op == 0x4056ceb8) {
            transferAuctionPayload = self.loadTransferAuctionPayload((msg.custom_payload!!).asSlice());
        }
        let isSentByAuction: Bool = (transferAuctionPayload != null) && (ctx.sender == self.get_nft_auction_address((transferAuctionPayload!!).seller));
        let isWhitelisted: Bool = ctx.sender == self.fraction_params.author || ctx.sender == self.collection_address  || isSentByAuction; // TODO: add Fraction auction contract
        if (isWhitelisted || self.quota > 0) {
            if (self.quota > 0 && !isWhitelisted) {
                self.quota = self.quota - 1;
            }
            self.owner = msg.new_owner;
            if (msg.forward_amount > 0) {
                send(SendParameters{
                    to: msg.new_owner,
                    value: msg.forward_amount,
                    mode: SendIgnoreErrors, 
                    bounce: false,
                    body: OwnershipAssigned{
                        query_id: msg.query_id,
                        prev_owner: ctx.sender,
                        forward_payload: msg.forward_payload
                    }.toCell()
                });
            }
            remain = remain - ctx.readForwardFee(); 
            if (msg.response_destination != newAddress(0, 0) && remain > msg.forward_amount) { 
                send(SendParameters{ 
                    to: msg.response_destination,
                    value: 0,
                    mode: SendRemainingValue,
                    body: Excesses { query_id: msg.query_id }.toCell()
                });
            }
        } else {
            self.fractionalize_validate(ctx);
            self.fractionalize(ctx);
        }
    }

}

contract NFTItemAuction {
    const minTonsForStorage: Int = ton("0.03");
    const gasConsumption: Int = ton("0.03");
    nft_item: Address;
    seller: Address;
    auctionInfo: AuctionInfo;
    auctionBidPeriod: Int;
    isInitialized: Int;
    auctionEndTime: Int;

    init(nft_item: Address, seller: Address) {
        self.nft_item = nft_item;
        self.seller = seller;
        self.isInitialized = 0;
        self.auctionBidPeriod = 0;
        self.auctionEndTime = 0;
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

    receive(msg: BuildNftAuction) {
        let ctx: Context = context();
        self._owner_validate(ctx);
        self._initialized_validate();
        self._set_price_validate(msg.auctionInfo.buyNowPrice, msg.auctionInfo.reservePrice);
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
        if(bidValue >= buyNowPrice && buyNowPrice != 0) {
            self.auctionInfo.nftHighestBid = bidValue;
            // Pay winning bid amount to seller.
            self._send_winning_bid_amount();
            // Transfer NFT to buyer
            self._transfer_nft(buyer);
            self.isInitialized = 0;
            return;
        }

        let bidIncreaseAmount: Int = (self.auctionInfo.nftHighestBid * (10000 + self.auctionInfo.bidIncreasePercentage)) / 10000;
        require(bidValue > bidIncreaseAmount || buyNowPrice == 0, "Bid doesn't meet the minimum increase requirement");
        //require(buyNowPrice != 0 && )
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
        self._owner_validate(ctx);
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

    inline fun _initialized_validate() {
        require(self.isInitialized == 0, "Contract is already initialized");
    }

    inline fun _owner_validate(ctx: Context) {
        require(ctx.sender == self.nft_item, "NFTItemAuction: Only the NFT Item contract can build the auction");
    }

    inline fun _set_price_validate(buyNowPrice: Int, reservePrice: Int) {
        require(buyNowPrice > reservePrice, "BuyNowPrice must be greater than reservePrice.");
    }

     // @dev Updates the auction bid period time based on the latest bid and the defined auction bid period
    inline fun _update_auction_bid_period() {
        self.auctionBidPeriod = now() + self.auctionInfo.auctionBidPeriod;
    }

    // @dev Updates the auction end time
    inline fun _update_auction_end_time() {
        self.auctionEndTime = now() + self.auctionInfo.auctionPeriod;
    }

    // @dev Transfer the NFT to the highest bidder
    // @note If you want change msg value, you should make sure that is enough for NFT Auction market contract to transfer NFT.
    inline fun _transfer_nft(buyer: Address) {
        let custom_payload: Cell = beginCell().storeAddress(self.auctionInfo.nftSeller).endCell();
        send(SendParameters{
            to: self.nft_item, 
            value: ton("0.06"), 
            bounce: true,
            mode: SendPayGasSeparately,
            body: Transfer {
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
    inline fun _send_winning_bid_amount() {
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
    inline fun _init_auction_end() {
        let ctx: Context = context();
        require(ctx.sender == self.nft_item, "Only NFT Item can init auction end time.");
        self.auctionBidPeriod = 0;
    }

    //*********************************//
    //             Getters             //
    //*********************************//

    // @dev Returns the current auction information
    get fun get_auction_info(): AuctionInfo {
        return self.auctionInfo;
    }

    // @dev Checks if the auction is initialized and returns the state (1 for initialized, 0 otherwise)
    get fun get_is_initialized(): Int {
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
