import { Blockchain, SandboxContract, TreasuryContract } from '@ton-community/sandbox';
import '@ton-community/test-utils';
import { sha256_sync } from 'ton-crypto';
import { FNFTCollection, FractionParams, RoyaltyParams } from '../../wrappers/FNFTCollection';
import { Cell, Dictionary, beginCell, toNano } from 'ton-core';

const OFFCHAIN_TAG = 0x01;
const BASE_URL = 'https://s.getgems.io/nft-staging/c/628f6ab8077060a7a8d52d63/';

describe('NFTFractionAuctionExample', () => {
    let blockchain: Blockchain;
    let alan: SandboxContract<TreasuryContract>;
    let jacky: SandboxContract<TreasuryContract>;
    let nftCollection: SandboxContract<FNFTCollection>;

    async function deployNFTCollection(deployer: SandboxContract<TreasuryContract>) {
        const nft_content: Cell = beginCell().endCell();
        const royalty_params: RoyaltyParams = {
            $$type: 'RoyaltyParams',
            numerator: 800n,
            denominator: 1000n,
            destination: deployer.address,
        };
        nftCollection = blockchain.openContract(
            await FNFTCollection.fromInit(alan.address, nft_content, royalty_params)
        );
        return await nftCollection.send(
            alan.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            }
        );
    }
    async function mintNFTItem(owner: SandboxContract<TreasuryContract>) {
        // mint NFT item to owner
        const res = await nftCollection.send(
            owner.getSender(),
            {
                value: toNano('1'),
            },
            'Mint'
        );
        return res;
    }

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        alan = await blockchain.treasury('alan');
        jacky = await blockchain.treasury('jacky');

        await deployNFTCollection(alan);
    });

    it('should deploy', async () => {
        expect(nftCollection.address).toBeTruthy();
    });

    it('should mint 1 token to Alan', async () => {
        // Mint 1 token to Alan
        let res = await mintNFTItem(alan);
        expect(res.transactions).toHaveTransaction({
            from: alan.address,
            to: nftCollection.address,
            success: true,
        });
    });

    it('should mint 1 token to Jacky', async () => {
        // Mint 1 token to Jacky
        let res = await mintNFTItem(jacky);
        expect(res.transactions).toHaveTransaction({
            from: jacky.address,
            to: nftCollection.address,
            success: true,
        });
    });
});
