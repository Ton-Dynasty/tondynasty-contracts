import { Blockchain, SandboxContract, TreasuryContract } from '@ton-community/sandbox';
import { FNFTCollection, FractionParams, RoyaltyParams } from '../wrappers/FNFT_FNFTCollection';
import '@ton-community/test-utils';
import { sha256_sync } from 'ton-crypto';
import { Cell, Dictionary, beginCell, toNano } from 'ton-core';
import { ExampleJettonMaster } from '../wrappers/JettonExample_ExampleJettonMaster';

const OFFCHAIN_TAG = 0x01;
const BASE_URL = 'https://s.getgems.io/nft-staging/c/628f6ab8077060a7a8d52d63/';

describe('NFTFractoinalizeExample', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let collectionContent: Cell;
    let nftcollection: SandboxContract<FNFTCollection>;
    let royaltyParams: RoyaltyParams;

    const ONCHAIN_CONTENT_PREFIX = 0x00;
    const SNAKE_PREFIX = 0x00;
    const CELL_MAX_SIZE_BYTES = Math.floor((1023 - 8) / 8);

    function bufferToChunks(buff: Buffer, chunkSize: number) {
        let chunks: Buffer[] = [];
        while (buff.byteLength > 0) {
            chunks.push(buff.slice(0, chunkSize));
            buff = buff.slice(chunkSize);
        }
        return chunks;
    }

    function makeSnakeCell(data: Buffer) {
        const chunks = bufferToChunks(data, 127);

        if (chunks.length === 0) {
            return beginCell().endCell();
        }

        if (chunks.length === 1) {
            return beginCell().storeBuffer(chunks[0]).endCell();
        }

        let curCell = beginCell();

        for (let i = chunks.length - 1; i >= 0; i--) {
            const chunk = chunks[i];

            curCell.storeBuffer(chunk);

            if (i - 1 >= 0) {
                const nextCell = beginCell();
                nextCell.storeRef(curCell);
                curCell = nextCell;
            }
        }

        return curCell.endCell();
    }

    const toKey = (key: string) => {
        return BigInt(`0x${sha256_sync(key).toString('hex')}`);
    };

    function buildOnchainMetadata(data: { name: string; description: string; symbol: string }): Cell {
        let dict = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Cell());
        Object.entries(data).forEach(([key, value]) => {
            dict.set(toKey(key), makeSnakeCell(Buffer.from(value, 'utf8')));
        });

        return beginCell().storeInt(ONCHAIN_CONTENT_PREFIX, 8).storeDict(dict).endCell();
    }

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        deployer = await blockchain.treasury('deployer');
        royaltyParams = {
            $$type: 'RoyaltyParams',
            numerator: 4n,
            denominator: 100n,
            destination: deployer.address,
        };
        collectionContent = beginCell().storeInt(OFFCHAIN_TAG, 8).storeStringRefTail(BASE_URL).endCell();
        nftcollection = blockchain.openContract(
            await FNFTCollection.fromInit(deployer.address, collectionContent, royaltyParams)
        );

        const deployResult = await nftcollection.send(
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
            to: nftcollection.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and nFTCollection are ready to use
    });

    it('TEST', async () => {
        const jettonParams = {
            name: 'F-TonDynasty #1',
            description: '1',
            symbol: 'F-TDT #1',
        };
        const onchainContent = buildOnchainMetadata(jettonParams);
        console.log('onchainContent:\n', onchainContent);
        let contentCell: Cell = (await nftcollection.getDebugFractionParam(1n)).jetton_content;
        console.log('contentCell:\n', contentCell);
        expect(contentCell.toString()).toEqual(onchainContent.toString());
    });
});
