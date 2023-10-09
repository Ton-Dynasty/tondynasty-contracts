import { Blockchain, SandboxContract, TreasuryContract } from '@ton-community/sandbox';
import { Cell, beginCell, toNano } from 'ton-core';
import { ExampleNFTCollection, RoyaltyParams } from '../wrappers/NFTExample';
import '@ton-community/test-utils';
import { ExampleNFTItem } from '../build/NFTExample/tact_ExampleNFTItem';

describe('NFTExample', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let collectionContent: Cell;
    let royaltyParams: RoyaltyParams;
    let nftCollection: SandboxContract<ExampleNFTCollection>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        deployer = await blockchain.treasury('deployer');
        collectionContent = beginCell().storeStringRefTail('Hello').endCell();
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

    it('should mint NFT', async () => {
        const newOwner = await blockchain.treasury('newOwner');
        const customPayload = beginCell().storeStringRefTail('World').endCell();

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

        const nftItem = blockchain.openContract(
            await ExampleNFTItem.fromInit(nftCollection.address, 0n, newOwner.address, beginCell().endCell())
        );
    });
});
