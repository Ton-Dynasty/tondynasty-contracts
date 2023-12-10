import {
    Blockchain,
    SandboxContract,
    TreasuryContract,
    prettyLogTransactions,
    printTransactionFees,
} from '@ton-community/sandbox';
import { Cell, beginCell, toNano } from 'ton-core';
import { MathExample } from '../../wrappers/MathExample';
import '@ton-community/test-utils';
import { Decimal } from 'decimal.js';

function toFloat(value: number, decimals: number = 64): bigint {
    const d = new Decimal(value).mul(new Decimal(2).pow(decimals)).floor();
    return BigInt(d.toString());
}

describe('MathExample', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let mathContract: SandboxContract<MathExample>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        deployer = await blockchain.treasury('deployer');
        const jetton_content: Cell = beginCell().endCell();
        mathContract = blockchain.openContract(await MathExample.fromInit());
        const deployResult = await mathContract.send(
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
            to: mathContract.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and nFTCollection are ready to use
    });

    it('2 + 7', async () => {
        const addResult = await mathContract.getAdd();
        const safeAddResult = await mathContract.getSafeAdd();
        const actualFloatResult = await mathContract.getFloat(9n);
        expect(actualFloatResult).toEqual(166020696663385964544n);
        expect(addResult).toEqual(actualFloatResult);
        expect(safeAddResult).toEqual(actualFloatResult);
    });

    it('2 - 7', async () => {
        const subResult = await mathContract.getSub();
        const safeSubResult = await mathContract.getSafeSub();
        const actualFloatResult = await mathContract.getFloat(-5n);
        expect(actualFloatResult).toEqual(-92233720368547758080n);
        expect(subResult).toEqual(actualFloatResult);
        expect(safeSubResult).toEqual(actualFloatResult);
    });

    it('2 * 7', async () => {
        const mulResult = await mathContract.getMul();
        const safeMulResult = await mathContract.getSafeMul();
        const actualFloatResult = await mathContract.getFloat(14n);
        expect(actualFloatResult).toEqual(258254417031933722624n);
        expect(mulResult).toEqual(actualFloatResult);
        expect(safeMulResult).toEqual(actualFloatResult);
    });

    it('2 / 7', async () => {
        const divResult = await mathContract.getDiv();
        const safeDivResult = await mathContract.getSafeDiv();
        expect(divResult).toEqual(5270498306774157604n);
        expect(safeDivResult).toEqual(5270498306774157604n);
    });

    it('Should throw errorCode 4 if div by 0', async () => {
        await mathContract.getDivisionByZero().catch((e) => {
            expect(e.exitCode).toEqual(4);
        });
    });

    it('0.25 + 10', async () => {
        const addTxs = await mathContract.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Arithmetic',
                floatA: toFloat(0.25),
                floatB: toFloat(10),
                op: 0n,
            }
        );
        console.log('Add');
        printTransactionFees(addTxs.transactions);
        const addResult = await mathContract.getResult();
        expect(Number(addResult)).toBeCloseTo(Number(toFloat(10.25)));
    });

    it('0.25 - 10', async () => {
        const subTxs = await mathContract.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Arithmetic',
                floatA: toFloat(0.25),
                floatB: toFloat(10),
                op: 1n,
            }
        );
        console.log('Sub');
        printTransactionFees(subTxs.transactions);
        const subResult = await mathContract.getResult();
        expect(Number(subResult)).toBeCloseTo(Number(toFloat(-9.75)));
    });

    it('0.25 * 10', async () => {
        const mulTxs = await mathContract.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Arithmetic',
                floatA: toFloat(0.25),
                floatB: toFloat(10),
                op: 2n,
            }
        );
        console.log('Mul');
        printTransactionFees(mulTxs.transactions);
        const mulResult = await mathContract.getResult();
        expect(Number(mulResult)).toBeCloseTo(Number(toFloat(2.5)));
    });

    it('0.25 / 10', async () => {
        const divTxs = await mathContract.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Arithmetic',
                floatA: toFloat(0.25),
                floatB: toFloat(10),
                op: 3n,
            }
        );
        console.log('Div');
        printTransactionFees(divTxs.transactions);
        const divResult = await mathContract.getResult();
        expect(Number(divResult)).toBeCloseTo(Number(toFloat(0.025)));
    });

    it('Sqrt 0.05', async () => {
        const sqrtTxs = await mathContract.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Arithmetic',
                floatA: toFloat(0.25),
                floatB: 0n,
                op: 4n,
            }
        );
        console.log('Sqrt');
        printTransactionFees(sqrtTxs.transactions);
        const sqrtResult = await mathContract.getResult();
        expect(Number(sqrtResult)).toBeCloseTo(Number(toFloat(0.5)));
    });

    it('Sqrt 25', async () => {
        const sqrtTxs = await mathContract.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Arithmetic',
                floatA: toFloat(25),
                floatB: 0n,
                op: 4n,
            }
        );
        console.log('Sqrt');
        printTransactionFees(sqrtTxs.transactions);
        const sqrtResult = await mathContract.getResult();
        expect(Number(sqrtResult)).toBeCloseTo(Number(toFloat(5)));
    });
});
