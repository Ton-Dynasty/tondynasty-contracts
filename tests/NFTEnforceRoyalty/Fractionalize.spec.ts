import {
    Blockchain,
    SandboxContract,
    TreasuryContract,
    prettyLogTransaction,
    prettyLogTransactions,
    printTransactionFees,
} from '@ton-community/sandbox';
import { Address, Cell, Sender, beginCell, toNano } from 'ton-core';
import { FNFTCollection, FractionParams, RoyaltyParams } from '../../wrappers/FNFTEnforce_FNFTCollection';
import { NFTFraction } from '../../wrappers/FNFTEnforce_NFTFraction';
import { FNFTItem, JettonTransfer } from '../../wrappers/FNFTEnforce_FNFTItem';
import { buildJettonContent, buildNFTCollectionContent } from '../../utils/ton-tep64';
import '@ton-community/test-utils';
import { QuotaShop } from '../../wrappers/FNFTEnforce_QuotaShop';

describe('NFTExample', () => {
    let blockchain: Blockchain;
    let alan: SandboxContract<TreasuryContract>;
    let jacky: SandboxContract<TreasuryContract>;
    let author: SandboxContract<TreasuryContract>;
    let nftCollection: SandboxContract<FNFTCollection>;
    let nftItem: SandboxContract<FNFTItem>;
    let quotaShop: SandboxContract<QuotaShop>;
    let royaltyParams: RoyaltyParams;
    let collectionContent: Cell;
    let fractionParams: FractionParams;
    const reservePrice: bigint = toNano('0.01');
    const maxSupply: bigint = 100n;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        alan = await blockchain.treasury('alan');
        jacky = await blockchain.treasury('jacky');
        author = await blockchain.treasury('author');
        collectionContent = buildNFTCollectionContent();
        royaltyParams = {
            $$type: 'RoyaltyParams',
            numerator: 1n,
            denominator: 100n,
            destination: author.address,
        };
        nftCollection = blockchain.openContract(
            await FNFTCollection.fromInit(alan.address, collectionContent, royaltyParams, author.address)
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

    it('Should Alan mint NFT#1 and full transfer to Jacky', async () => {
        const beforeItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;

        // Alan mint NFT#1
        const mintResult = await nftCollection.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            'Mint'
        );

        // Check Alan send a transaction to NFTCollection
        expect(mintResult.transactions).toHaveTransaction({
            from: alan.address,
            to: nftCollection.address,
            deploy: false,
            success: true,
        });

        // Check NFTCollection deploys a new NFTItem
        const nftItemAddr = await nftCollection.getGetNftAddressByIndex(beforeItemIndex);
        expect(mintResult.transactions).toHaveTransaction({
            from: nftCollection.address,
            to: nftItemAddr,
            deploy: true,
            success: true,
        });

        // Check NFTCollection deploys a new QuotaShop
        const quotaShopAddr = await nftCollection.getDebugGetQuotashopAddressByIndex(beforeItemIndex);
        expect(mintResult.transactions).toHaveTransaction({
            from: nftCollection.address,
            to: quotaShopAddr,
            deploy: true,
            success: true,
        });

        // Check NFTCollection index increased by 1
        const afterItemIndex = (await nftCollection.getGetCollectionData()).next_item_index;
        expect(afterItemIndex).toEqual(beforeItemIndex + 1n);

        // Should Alan be the owner of NFT#1
        const nftItem = blockchain.openContract(FNFTItem.fromAddress(nftItemAddr));
        const owner = await nftItem.getOwner();
        expect(owner.toString()).toEqual(alan.address.toString());

        // Should Author issue quota to QuotaShop #1
        quotaShop = blockchain.openContract(QuotaShop.fromAddress(quotaShopAddr));
        const quotaIssueTx = await quotaShop.send(
            author.getSender(),
            {
                value: toNano('0.01'),
            },
            {
                $$type: 'IssueQuota',
                amount: 1n,
                price: toNano('0.01'),
            }
        );
        expect(quotaIssueTx.transactions).toHaveTransaction({
            from: author.address,
            to: quotaShopAddr,
            deploy: false,
            success: true,
        });

        // Buy one quota from QuotaShop#1 should increase the NFT item #1 quota by 1
        const quotaBefore = await nftItem.getDebugGetQuota();
        quotaShop = blockchain.openContract(QuotaShop.fromAddress(quotaShopAddr));
        const buyResult = await quotaShop.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'BuyQuota',
                amount: 1n,
            }
        );
        expect(buyResult.transactions).toHaveTransaction({
            from: alan.address,
            to: quotaShopAddr,
            deploy: false,
            success: true,
        });
        expect(buyResult.transactions).toHaveTransaction({
            from: quotaShopAddr,
            to: nftItemAddr,
            deploy: false,
            success: true,
        });
        expect(buyResult.transactions).toHaveTransaction({
            from: nftItemAddr,
            to: alan.address,
            deploy: false,
            success: true,
        });
        const quotaAfter = await nftItem.getDebugGetQuota();
        expect(quotaAfter).toEqual(quotaBefore + 1n);
    });
});
