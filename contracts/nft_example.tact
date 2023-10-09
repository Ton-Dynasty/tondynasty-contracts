import "@stdlib/deploy";
import "./packages/token/nft/NFTCollection";
import "./packages/token/nft/extensions/NFTRoyalty";
import "./packages/token/nft/NFTItem";

contract ExampleNFTCollection with NFTCollectionStandard, NFTRoyaltyStandard, Deployable {
    next_item_index: Int as uint32 = 0; // if next_item_index is not -1, means sequential minting is enabled. We want a sequential minting in this example so we set it to uint32.
    collection_content: Cell;           // collection_content may be the prefix of individual_content
    owner_address: Address;             // owner_address is the address of the owner of the collection
    royalty_params: RoyaltyParams;      // royalty_params is the params of royalty
    
    content_map: map<Int as uint32, Cell>;        // content_map is a customize map of index to individual_content

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
        let rndContentBuilder: StringBuilder = beginString();
        rndContentBuilder.append(randomInt().toString());
        send(SendParameters{
                to: contractAddress(nftItemInit), 
                value: 0, 
                bounce: false,
                mode: SendIgnoreErrors,
                body: Transfer {
                    query_id: 0,
                    new_owner: ctx.sender,
                    response_destination: self.owner_address,
                    custom_payload: rndContentBuilder.toCell(),
                    forward_amount: 0,
                    forward_payload: emptyCell()
                }.toCell(),
                code: nftItemInit.code,
                data: nftItemInit.data
            });
        self.content_map.set(self.next_item_index, rndContentBuilder.toCell());
        self.next_item_index = self.next_item_index + 1;
    }

    // @dev _get_nft_item_state_init returns the initCode of NFTItem
    override inline fun _get_nft_item_state_init(index: Int): StateInit {
        return initOf ExampleNFTItem(myAddress(), index, self.owner_address, emptyCell());
    }

    // @dev _get_nft_content concat collction_content and individual_content as example
    //      for example, if collection_content is "https://example.com/collection/<address>/"
    //      and individual_content is "alankingdom", then the result is "https://example.com/collection/<address>/alankingdom"
    override inline fun _get_nft_content(index: Int, individual_content: Cell): Cell {
        let builder: StringBuilder = beginString();
        let contentStr: String = self.collection_content.asSlice().asString();
        let idvStr: String = individual_content.asSlice().asString();
        builder.append(contentStr);
        builder.append(idvStr);
        return builder.toCell();
    }
}

contract ExampleNFTItem with NFTItemStandard {
    override const gasConsumption: Int = ton("0.03");

    collection_address: Address;
    index: Int;
    owner: Address;
    individual_content: Cell;
    is_initialized: Bool = false;
    
    init(collection_address: Address, index: Int, owner: Address, individual_content: Cell) {
        self.collection_address = collection_address;
        self.index = index;
        self.owner = owner;
        self.individual_content = individual_content;
    }

    // @dev _process_initialize is called by NFTCollection when NFTItem is minted
    //      when NFTItem is minted, the owner of NFTItem is the owner of NFTCollection
    //      and the individual_content is the custom_payload of the minting request
    override inline fun _process_initialize(ctx: Context, msg: Transfer){
        self.is_initialized = true;
        if (msg.custom_payload != null){
            self.individual_content = msg.custom_payload!!;
        }
        send(SendParameters{
            to: msg.response_destination,
            value: 0,
            mode:  SendIgnoreErrors + SendRemainingValue,
            body: Excesses { query_id: msg.query_id }.toCell()
        });
    }

    // @dev getter function for testing purpose
    get fun get_is_initialized(): Bool {
        return self.is_initialized;
    }

}