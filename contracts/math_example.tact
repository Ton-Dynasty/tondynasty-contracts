import "./packages/math/float.fc";
import "@stdlib/deploy";

@name(toFloat)
extends native toFloat(self: Int): Int;

@name(safeAdd)
extends native safeAdd(self: Int, b: Int): Int;

@name(safeSub)
extends native safeSub(self: Int, b: Int): Int;

@name(safeMul)
extends native safeMul(self: Int, b: Int): Int;

@name(safeDiv)
extends native safeDiv(self: Int, b: Int): Int;

@name(add)
extends native add(self: Int, b: Int): Int;

@name(sub)
extends native sub(self: Int, b: Int): Int;

@name(mul)
extends native mul(self: Int, b: Int): Int;

@name(div)
extends native div(self: Int, b: Int): Int;

@name(sqrtFloat)
extends native sqrtFloat(self: Int): Int;

message Arithmetic {
    floatA: Int;
    floatB: Int;
    op: Int; // 0: add, 1: sub, 2: mul, 3: div
}

contract MathExample with Deployable {
    x: Int = 2;
    y: Int = 7;
    result: Int = 0;
    init(){}

    receive(msg: Arithmetic){
        if (msg.op == 0) {
            self.result = msg.floatA.safeAdd(msg.floatB);
            return ;
        }
        if (msg.op == 1) {
            self.result = msg.floatA.safeSub(msg.floatB);
            return ;
        }
        if (msg.op == 2) {
            self.result = msg.floatA.safeMul(msg.floatB);
            return ;
        }
        if (msg.op == 3) {
            self.result = msg.floatA.safeDiv(msg.floatB);
            return ;
        }
        if (msg.op == 4) {
            self.result = msg.floatA.sqrtFloat();
            return ;
        }
    }

    get fun float(value: Int): Int {
        return value.toFloat();
    }

    get fun safeAdd(): Int {
        let a: Int = self.x.toFloat();
        let b: Int = self.y.toFloat();
        return a.safeAdd(b);
    }

    get fun safeSub(): Int {
        let a: Int = self.x.toFloat();
        let b: Int = self.y.toFloat();
        return a.safeSub(b);
    }

    get fun safeMul(): Int {
        let a: Int = self.x.toFloat();
        let b: Int = self.y.toFloat();
        return a.safeMul(b);
    }

    get fun safeDiv(): Int {
        let a: Int = self.x.toFloat();
        let b: Int = self.y.toFloat();
        return a.safeDiv(b);
    }

    get fun Add(): Int {
        let a: Int = self.x.toFloat();
        let b: Int = self.y.toFloat();
        return a.add(b);
    }

    get fun Sub(): Int {
        let a: Int = self.x.toFloat();
        let b: Int = self.y.toFloat();
        return a.sub(b);
    }

    get fun Mul(): Int {
        let a: Int = self.x.toFloat();
        let b: Int = self.y.toFloat();
        return a.mul(b);
    }

    get fun Div(): Int {
        let a: Int = self.x.toFloat();
        let b: Int = self.y.toFloat();
        return a.div(b);
    }

    get fun DivisionByZero(): Int {
        // expected to throw error code 4
        let a: Int = self.x.toFloat();
        let b: Int = 0;
        return a.div(b);
    }

    get fun Result(): Int {
        return self.result;
    }
}