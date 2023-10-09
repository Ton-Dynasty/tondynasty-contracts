import { sha256_sync } from 'ton-crypto';
import { Cell, Dictionary, beginCell, toNano } from 'ton-core';
import { ExampleJettonMaster } from '../wrappers/JettonExample';
import { NetworkProvider } from '@ton-community/blueprint';

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
    let chunks = bufferToChunks(data, CELL_MAX_SIZE_BYTES);
    const b = chunks.reduceRight((curCell, chunk, index) => {
        if (index === 0) {
            curCell.storeInt(SNAKE_PREFIX, 8);
        }
        curCell.storeBuffer(chunk);
        if (index > 0) {
            const cell = curCell.endCell();
            return beginCell().storeRef(cell);
        } else {
            return curCell;
        }
    }, beginCell());
    return b.endCell();
}

const toKey = (key: string) => {
    return BigInt(`0x${sha256_sync(key).toString('hex')}`);
};

function buildOnchainMetadata(data: { name: string; description: string; image: string; symbol: string }): Cell {
    let dict = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Cell());
    Object.entries(data).forEach(([key, value]) => {
        dict.set(toKey(key), makeSnakeCell(Buffer.from(value, 'utf8')));
    });

    return beginCell().storeInt(ONCHAIN_CONTENT_PREFIX, 8).storeDict(dict).endCell();
}

export async function run(provider: NetworkProvider) {
    const deployer = provider.sender();
    console.log('Deploying contract with deployer address', deployer.address);
    const jettonParams = {
        name: 'TonDynasty',
        description: 'TonDynasty Co-Founder Certificate - Tact',
        symbol: 'TDT',
        image: 'https://avatars.githubusercontent.com/u/144251015?s=400&u=a25dfca41bdc6467d9783f5225c93f60e1513630&v=4',
    };
    const onchainContent = buildOnchainMetadata(jettonParams);
    const nFTCollection = provider.open(await ExampleJettonMaster.fromInit(deployer.address!, onchainContent));
    await nFTCollection.send(
        provider.sender(),
        {
            value: toNano('0.03'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

    await provider.waitForDeploy(nFTCollection.address);
}
