import "@stdlib/deploy";
import "./packages/token/nft/NFTCollection";
import "./packages/token/nft/extensions/NFTRoyalty";
import "./packages/token/nft/NFTItem";
import "./packages/utils/GasEstimate";
import "./packages/token/jetton/JettonMaster";
import "./packages/token/jetton/JettonWallet";

contract NFTFractionWallet with JettonWallet {
    balance: Int as coins = ton("0");
    owner: Address;
    jetton_master: Address;

    init(owner: Address, jetton_master: Address) {
        self.owner = owner;
        self.jetton_master = jetton_master;
    }

    override inline fun _get_jetton_wallet_code(): Cell {
        return initOf NFTFractionWallet(self.owner, self.jetton_master).code;
    }
}

contract NFTFraction with JettonMaster {
    total_supply: Int as coins;
    mintable: Bool;
    owner: Address;
    jetton_content: Cell;

    init(total_supply: Int, mintable: Bool, owner: Address, jetton_content: Cell) {
        self.total_supply = total_supply;
        self.mintable = mintable;
        self.owner = owner;
        self.jetton_content = jetton_content;
    }

    override inline fun _get_jetton_wallet_init(owner_address: Address): StateInit {
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

    // @dev _get_nft_item_state_init returns the initCode of NFTItem
    override inline fun _get_nft_item_state_init(index: Int): StateInit {
        return initOf FNFTItem(myAddress(), index, self.owner_address, self.collection_content);
    }
}

contract FNFTItem with NFTItemStandard {
    override const gasConsumption: Int = ton("0.06");

    collection_address: Address;
    index: Int;
    owner: Address;
    individual_content: Cell;
    is_initialized: Bool = false;
    is_locked: Bool = false;
    
    init(collection_address: Address, index: Int, owner: Address, individual_content: Cell) {
        self.collection_address = collection_address;
        self.index = index;
        self.owner = owner;
        self.individual_content = individual_content;
    }

    receive("Redeem") {
        let ctx: Context = context();
        require(self.is_locked == true, "FNFTItem: Only the locked NFT item can be redeemed");
        self.redeem(ctx);
    }

    receive("Fractionalize"){
        let ctx: Context = context();
        require(ctx.sender == self.owner || ctx.sender == self.collection_address, "FNFTItem: Only the owner or collection can fractionalize");
        self.fractionalize(ctx);
    }

    inline fun fractionalize(ctx: Context) {
        self.is_locked = true;
    }

    inline fun redeem(ctx: Context) {
        self.is_locked = false;
    }

    override inline fun _validate_transfer(ctx: Context, msg: Transfer, remain: Int) {
        require(ctx.sender == self.owner || ctx.sender == self.collection_address, "FNFTItem: Only the owner or collection can transfer the NFT item");
        require(self.is_locked == false, "FNFTItem: The NFT item is locked");
    }

    override inline fun _process_transfer(ctx: Context, msg: Transfer, remain: Int) {
        if(ctx.sender == self.collection_address) {
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
            if (msg.response_destination != newAddress(0, 0)) { 
                send(SendParameters{ 
                    to: msg.response_destination,
                    value: remain - msg.forward_amount,
                    mode: SendPayGasSeparately,
                    body: Excesses { query_id: msg.query_id }.toCell()
                });
            }
        } else {

        }
    }
}
