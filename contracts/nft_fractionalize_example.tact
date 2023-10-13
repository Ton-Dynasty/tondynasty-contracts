import "@stdlib/deploy";
import "@stdlib/ownable";
import "./packages/token/nft/NFTCollection";
import "./packages/token/nft/extensions/NFTRoyalty";
import "./packages/token/nft/NFTItem";
import "./packages/token/jetton/JettonMaster";
import "./packages/token/jetton/JettonWallet";
import "./packages/utils/Estimatable";
import "./packages/utils/Lockable";

@name(udict_set_ref)
native udict_set_ref(dict: Cell?, key_len: Int, index: Int, value: Cell): Cell?; 

message FractionParams {
    max_supply: Int as coins;
    jetton_content: Cell;
}

message(0xbaa13f5f) TryRedeem {
    sender: Address; // Request sender who sent "Redeem" message to NFT Item
}

message(0xbac2f9a4) Compose {
    new_owner: Address;
}

contract NFTFractionWallet with JettonWallet {
    balance: Int as coins = ton("0");
    owner: Address;
    jetton_master: Address;

    init(owner: Address, jetton_master: Address) {
        self.owner = owner;
        self.jetton_master = jetton_master;
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

    max_supply: Int as coins;

    init(max_supply: Int, owner: Address, jetton_content: Cell) {
        self.max_supply = max_supply;
        self.owner = owner;
        self.jetton_content = jetton_content;
    }

    receive(msg: TryRedeem) {
        require(self.total_supply == self.max_supply, "NFTFraction: Total supply is not equal to max supply");
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
        require(self.total_supply + msg.amount <= self.max_supply, "JettonMaster: Exceeds max supply");
    }
}

contract FNFTCollection with NFTCollectionStandard, NFTRoyaltyStandard, Estimatable, Deployable {
    next_item_index: Int as uint32 = 0; // if next_item_index is not -1, means sequential minting is enabled. We want a sequential minting in this example so we set it to uint32.
    collection_content: Cell;           // collection_content may be the prefix of individual_content
    owner_address: Address;             // owner_address is the address of the owner of the collection
    royalty_params: RoyaltyParams;      // royalty_params is the params of royalty
    //content_cell: map<Int, Cell> ;
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

    collection_address: Address;
    index: Int;
    owner: Address;
    individual_content: Cell;
    is_initialized: Bool = false;
    is_locked: Bool = false;

    fraction_params: FractionParams;
    
    init(collection_address: Address, index: Int, owner: Address, individual_content: Cell, fraction_params: FractionParams) {
        self.collection_address = collection_address;
        self.index = index;
        self.owner = owner;
        self.individual_content = individual_content;
        self.fraction_params = fraction_params;
    }

    receive("Fractionalize:2") {
        let ctx: Context = context();
        self.fractionalize_validate(ctx);
        self.fractionalize(ctx);
    }

    receive("Redeem:2") {
        self.ensureLocked();
        let ctx: Context = context();
        let nftFractionInit: StateInit = self.get_jetton_master_init();
        send(SendParameters{ 
            to: contractAddress(nftFractionInit),
            value: 0,
            mode: SendRemainingValue,
            body: TryRedeem { sender: ctx.sender }.toCell()
        });
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
    
    inline fun get_jetton_master_init(): StateInit {
        return initOf NFTFraction(self.fraction_params.max_supply, myAddress(), self.fraction_params.jetton_content);
    }

    inline fun fractionalize_validate(ctx: Context) {
        self.ensureUnlocked();
        self.requireOwner();
    }

    inline fun fractionalize(ctx: Context) {
        self.lock();
        self.owner = newAddress(0, 0);
        let nftFractionInit: StateInit = self.get_jetton_master_init();
        self.forward(
            contractAddress(nftFractionInit),
            JettonMint {
                origin: ctx.sender,
                receiver: ctx.sender, 
                amount: self.fraction_params.max_supply,
                custom_payload: emptyCell(),
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),
            false,
            nftFractionInit
        );
    }

    override inline fun _transfer_validate(ctx: Context, msg: Transfer, remain: Int) {
        self.ensureUnlocked();
        require(ctx.sender == self.owner || ctx.sender == self.collection_address, "FNFTItem: Only the owner or collection can transfer the NFT item");
    }
}
