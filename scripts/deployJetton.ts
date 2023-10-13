import { sha256_sync } from 'ton-crypto';
import { Cell, Dictionary, beginCell, toNano } from 'ton-core';
import { ExampleJettonMaster } from '../wrappers/JettonExample_ExampleJettonMaster';
import { NetworkProvider } from '@ton-community/blueprint';
import { buildJettonContent } from '../utils/ton-tep64';

export async function run(provider: NetworkProvider) {
    const deployer = provider.sender();
    console.log('Deploying contract with deployer address', deployer.address);
    const jettonContent = buildJettonContent({
        name: 'TonDynasty',
        description: 'TonDynasty Co-Founder Certificate - Tact',
        symbol: 'TDT',
        image: 'https://avatars.githubusercontent.com/u/144251015?s=400&u=a25dfca41bdc6467d9783f5225c93f60e1513630&v=4',
    });
    const nFTCollection = provider.open(await ExampleJettonMaster.fromInit(deployer.address!, jettonContent));
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
