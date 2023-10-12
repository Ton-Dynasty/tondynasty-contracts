import { Blockchain, SandboxContract, TreasuryContract } from '@ton-community/sandbox';
import { Cell, beginCell, toNano } from 'ton-core';
import { ExampleNFTCollection, RoyaltyParams } from '../wrappers/NFTExample_ExampleNFTCollection';
import '@ton-community/test-utils';

const OFFCHAIN_TAG = 0x01;
const BASE_URL = 'https://s.getgems.io/nft-staging/c/628f6ab8077060a7a8d52d63/';

describe('NFTExample', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let collectionContent: Cell;
    let royaltyParams: RoyaltyParams;
    let nftCollection: SandboxContract<ExampleNFTCollection>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        deployer = await blockchain.treasury('deployer');
        const collectionContent = beginCell().storeInt(OFFCHAIN_TAG, 8).storeStringRefTail(BASE_URL).endCell();
        royaltyParams = {
            $$type: 'RoyaltyParams',
            numerator: 4n,
            denominator: 100n,
            destination: deployer.address,
        };
        const initCode = await ExampleNFTCollection.fromInit(deployer.address, collectionContent, royaltyParams);
        nftCollection = blockchain.openContract(initCode);

        const deployResult = await nftCollection.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            }
        );

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: nftCollection.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and nFTCollection are ready to use
    });

    it('Should get collection metadata successfully', async () => {
        const collectionData = await nftCollection.getGetCollectionData();
        const parser = collectionData.collection_content.beginParse();
        const offchainTag = parser.loadUint(8).toString();
        const metadata = parser.loadStringTail().toString();
        expect(offchainTag).toEqual('1');
        expect(metadata).toEqual('https://s.getgems.io/nft-staging/c/628f6ab8077060a7a8d52d63/meta.json');
    });

    it('should mint NFT successfully', async () => {
        const before_index = (await nftCollection.getGetCollectionData()).next_item_index;

        const mintResult = await nftCollection.send(
            deployer.getSender(),
            {
                value: toNano('0.5'),
            },
            'Mint'
        );

        expect(mintResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: nftCollection.address,
            deploy: false,
            success: true,
        });

        // Check Index
        const after_index = (await nftCollection.getGetCollectionData()).next_item_index;
        expect(after_index).toEqual(before_index + 1n);
    });
});
