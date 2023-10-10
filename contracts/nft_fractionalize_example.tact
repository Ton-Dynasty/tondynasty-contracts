import "@stdlib/deploy";
import "@stdlib/ownable";
import "./packages/token/nft/NFTCollection";
import "./packages/token/nft/extensions/NFTRoyalty";
import "./packages/token/nft/NFTItem";
import "./packages/token/jetton/JettonMaster";
import "./packages/token/jetton/JettonWallet";
import "./packages/utils/Estimatable";
import "./packages/utils/Lockable";

message FractionParams {
    max_fraction_supply: Int as coins;
    jetton_content: Cell;
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
}

contract NFTFraction with JettonMaster {
    mintable: Bool = true;
    total_supply: Int as coins = 0;
    owner: Address;
    jetton_content: Cell;

    max_supply: Int as coins;

    init(max_supply: Int, owner: Address, jetton_content: Cell) {
        self.max_supply = max_supply;
        self.owner = owner;
        self.jetton_content = jetton_content;
    }

    override inline fun calculate_jetton_wallet_init(owner_address: Address): StateInit {
        return initOf NFTFractionWallet(owner_address, myAddress());
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
        require(self.owner_address == ctx.sender, "NFTCollectionMintable: only owner can mint");
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
                    forward_payload: emptyCell()
                }.toCell(),
                code: nftItemInit.code,
                data: nftItemInit.data
            });
        self.next_item_index = self.next_item_index + 1;
    }

    // TODO: need to calculate the jetton content
    inline fun get_fraction_param(index: Int): FractionParams {
        return FractionParams {
            max_fraction_supply: ton("100"),
            jetton_content: emptyCell()
        };
    }

    // @dev _get_nft_item_state_init returns the initCode of NFTItem
    override inline fun _get_nft_item_state_init(index: Int): StateInit {
        return initOf FNFTItem(myAddress(), index, self.owner_address, self.collection_content, self.get_fraction_param(index));
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

    receive("Redeem") {
        let ctx: Context = context();
        self.redeem_validate(ctx);
        self.redeem(ctx);
    }

    receive("Fractionalize") {
        let ctx: Context = context();
        self.fractionalize_validate(ctx);
        self.fractionalize(ctx);
    }

    inline fun fractionalize_validate(ctx: Context) {
        self.ensureUnlocked();
        self.requireOwner();
    }

    inline fun fractionalize(ctx: Context) {
        self.lock();
        let nftFractionInit: StateInit = initOf NFTFraction(self.fraction_params.max_fraction_supply, myAddress(), self.individual_content);
        self.forward(
            contractAddress(nftFractionInit),
            JettonMint {
                receiver: ctx.sender, 
                amount: self.fraction_params.max_fraction_supply
            }.toCell(),
            false,
            nftFractionInit
        );
    }

    inline fun redeem_validate(ctx: Context) {
        self.ensureLocked();
        self.requireOwner();
    }

    inline fun redeem(ctx: Context) {
        self.unlock();
    }

    override inline fun _transfer_validate(ctx: Context, msg: Transfer, remain: Int) {
        self.ensureUnlocked();
        require(ctx.sender == self.owner || ctx.sender == self.collection_address, "FNFTItem: Only the owner or collection can transfer the NFT item");
    }
}
