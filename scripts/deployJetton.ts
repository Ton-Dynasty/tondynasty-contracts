import { sha256_sync } from 'ton-crypto';
import { Cell, Dictionary, beginCell, toNano } from 'ton-core';
import { ExampleJettonMaster } from '../wrappers/JettonExample_ExampleJettonMaster';
import { NetworkProvider } from '@ton-community/blueprint';
import { buildJettonContent } from '../utils/ton-tep64';

export async function run(provider: NetworkProvider) {
    const deployer = provider.sender();
    console.log('Deploying contract with deployer address', deployer.address);
    const jettonContent = buildJettonContent({
        name: 'AlanKingdom',
        description: 'Alankingdom is a decentralized kingdom, where you can create your own kingdom and become a king.',
        symbol: 'ALL',
        decimals: '9',
        image: 'https://avatars.githubusercontent.com/u/144251015?s=400&u=a25dfca41bdc6467d9783f5225c93f60e1513630&v=4',
    });
    const jettonMaster = provider.open(await ExampleJettonMaster.fromInit(deployer.address!, jettonContent));
    await jettonMaster.send(
        provider.sender(),
        {
            value: toNano('0.1'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

    await provider.waitForDeploy(jettonMaster.address);
}
