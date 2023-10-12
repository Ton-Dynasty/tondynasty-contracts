import { Blockchain, SandboxContract, TreasuryContract, printTransactionFees } from '@ton-community/sandbox';
import { Address, Cell, Sender, beginCell, toNano } from 'ton-core';
import { FNFTCollection, FractionParams, RoyaltyParams } from '../../wrappers/FNFTCollection';
import { NFTFraction } from '../../wrappers/FNFTFraction';
import { FNFTItem, JettonTransfer } from '../../wrappers/FNFTItem';
import { buildJettonContent, buildNFTCollectionContent } from '../../utils/ton-tep64';
import '@ton-community/test-utils';

describe('NFTExample', () => {
    let blockchain: Blockchain;
    let alan: SandboxContract<TreasuryContract>;
    let jacky: SandboxContract<TreasuryContract>;
    let author: SandboxContract<TreasuryContract>;
    let nftCollection: SandboxContract<FNFTCollection>;
    let nftItem: SandboxContract<FNFTItem>;
    let royaltyParams: RoyaltyParams;
    let jettonContent: Cell;
    let fractionParams: FractionParams;
    const reservePrice: bigint = toNano('0.01');
    const maxSupply: bigint = 100n;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        alan = await blockchain.treasury('alan');
        jacky = await blockchain.treasury('jacky');
        author = await blockchain.treasury('author');
        jettonContent = beginCell().endCell();
        royaltyParams = {
            $$type: 'RoyaltyParams',
            numerator: 1n,
            denominator: 100n,
            destination: author.address,
        };
        nftCollection = blockchain.openContract(
            await FNFTCollection.fromInit(alan.address, jettonContent, royaltyParams, author.address)
        );
        const deployResult = await nftCollection.send(
            alan.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            }
        );

        expect(deployResult.transactions).toHaveTransaction({
            from: alan.address,
            to: nftCollection.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {});

    it('Should Alan mint NFT#1 and transfer to Jacky', async () => {
        // Alan mint NFT#1
        const mintResult = await nftCollection.send(
            alan.getSender(),
            {
                value: toNano('0.1'),
            },
            'Mint'
        );

        const beforeItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;

        // Check Alan send a transaction to NFTCollection
        expect(mintResult.transactions).toHaveTransaction({
            from: alan.address,
            to: nftCollection.address,
            deploy: false,
            success: true,
        });

        // Check NFTCollection deploys a new NFTItem
        fractionParams = {
            $$type: 'FractionParams',
            author: author.address,
            reserve_price: reservePrice,
            max_supply: maxSupply,
            jetton_content: buildJettonContent(beforeItemIndex),
        };
        nftItem = blockchain.openContract(
            await FNFTItem.fromInit(nftCollection.address, beforeItemIndex, alan.address, jettonContent, fractionParams)
        );
        expect(mintResult.transactions).toHaveTransaction({
            from: nftCollection.address,
            to: nftItem.address,
            deploy: true,
            success: true,
        });

        // Check NFTCollection index increased by 1
        const afterItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;
        expect(afterItemIndex).toEqual(beforeItemIndex + 1n);

        printTransactionFees(mintResult.transactions);
    });
});
