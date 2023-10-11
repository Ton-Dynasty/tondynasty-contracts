/*
    This file provides traits for NFT item which follows the TEP-0062 standard.
    https://github.com/ton-blockchain/TEPs/blob/master/text/0062-nft-standard.md

    Reference:
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-item.fc#L17)
    [NFT Template](https://github.com/howardpen9/nft-template-in-tact/blob/tutorial/sources/contract.tact)
*/


message(0x5fcc3d14) Transfer { 
    query_id: Int as uint64;                    // arbitrary request number
    new_owner: Address;                         // new owner of the NFT item
    response_destination: Address;              // address where to send a response with confirmation of a successful transfer and the rest of the incoming message coins if not empty address
    custom_payload: Cell?;                      // optional custom data
    forward_amount: Int as coins;               // the amount of nanotons to be sent to the new owner
    forward_payload: Slice as remaining;        // optional custom data that should be sent to the new owner
}

message(0x05138d91) OwnershipAssigned {
    query_id: Int as uint64;
    prev_owner: Address;
    forward_payload: Slice as remaining;
}

message(0xd53276db) Excesses {
    query_id: Int as uint64;
}

message(0x2fcb26a2) GetStaticData {
    query_id: Int as uint64;
}

message(0x8b771735) ReportStaticData {
    query_id: Int as uint64;
    index: Int as uint256;
    collection: Address;
}

struct NftData {
    is_initialized: Bool;         // it should be `init`, but it is a reserved keyword in tact. if not zero, then this NFT is fully initialized and ready for interaction.
    index: Int;                   // numerical index of this NFT in the collection. For collection-less NFT - arbitrary but constant value.
    collection_address: Address;  // address of the smart contract of the collection to which this NFT belongs. For collection-less NFT this parameter should be addr_none
    owner_address: Address;       // address of the current owner of this NFT
    individual_content: Cell;     // if NFT has collection - individual NFT content in any format; if NFT has no collection - NFT content in format that complies with standard TEP-64
}


trait NFTItemStandard {
    virtual const minTonsForStorage: Int = ton("0.05");
    virtual const gasConsumption: Int = ton("0.05");

    collection_address: Address;
    index: Int;
    owner: Address;
    individual_content: Cell;
    is_initialized: Bool;

    //********************************************//
    //                  Messages                  //
    //********************************************//

    receive(msg: Transfer){
        let ctx: Context = context();
        let remain: Int = self._transfer_estimate_rest_value(ctx);
        self._transfer_validate(ctx, msg, remain);
        if (self.is_initialized == false) {
            self.mint(ctx, msg);
        } else {
            self.transfer(ctx, msg, remain);
        }
    }

    receive(msg: GetStaticData){
        self._report_static_data(msg);
    }

    //********************************************//
    //             Internal functions             //
    //********************************************//

    // @dev  _transfer_estimate_rest_value calculates the remain amount of nanotons that should be sent back to the old owner
    inline fun _transfer_estimate_rest_value(ctx: Context): Int {
        let remain: Int = ctx.value;
        let tonBalanceBeforeMsg: Int = myBalance() - remain;
        let storageFee: Int = self.minTonsForStorage - min(tonBalanceBeforeMsg, self.minTonsForStorage);
        return remain - (storageFee + self.gasConsumption);
    }

    // @dev  _transfer_validate checks if the request is valid (e.g. the sender is the current owner of the NFT item)
    //       throws error if the request is invalid
    // @note one may override this function to implement custom validation logicTransferked
    virtual inline fun _transfer_validate(ctx: Context, msg: Transfer, remain: Int) {
        require(ctx.sender == self.owner || ctx.sender == self.collection_address, "NFTItemStandard: Only the owner or collection can transfer the NFT item");
    }

    // @dev  mint usually performs the minting of the NFT item
    // @note one may override this function to implement custom minting logic
    virtual inline fun mint(ctx: Context, msg: Transfer) {
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

    // @dev  transfer performs the transfer of the NFT item
    //      if available, it will send OwnershipAssigned message to the new owner
    //      then, it will send Excesses message to the response_destination (old owner) if needed.
    // @note one may override this function to implement custom transfer logic
    virtual inline fun transfer(ctx: Context, msg: Transfer, remain: Int) {
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
                value: remain - msg.forward_amount,
                mode: SendPayGasSeparately,
                body: Excesses { query_id: msg.query_id }.toCell()
            });
        }
    }

    // @dev  _report_static_data sends a response with the static data of the NFT item
    virtual inline fun _report_static_data(msg: GetStaticData) {
        let ctx: Context = context();
        send(SendParameters {
            to: ctx.sender,
            value: 0,
            mode: SendRemainingValue,
            bounce: false,
            body: ReportStaticData{
                query_id: msg.query_id,
                index: self.index,
                collection: self.collection_address
            }.toCell()
        });
    }

    // @dev  _get_nft_data returns the NFT data in the format that complies with TEP-64
    virtual inline fun _get_nft_data(): NftData {
        let builder: StringBuilder = beginString();
        let collectionData: String = self.individual_content.asSlice().asString();
        builder.append(collectionData);
        builder.append(self.index.toString());
        builder.append(".json");

        return NftData {
            is_initialized: self.is_initialized, 
            index: self.index, 
            collection_address: self.collection_address, 
            owner_address: self.owner,
            individual_content: builder.toCell()
        };
    }


    //*********************************//
    //             Getters             //
    //*********************************//
    get fun get_nft_data(): NftData {
        return self._get_nft_data();
    }
}