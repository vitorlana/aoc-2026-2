#!/usr/bin/env python3
"""Gera vetores de teste da ALU (a b op y) e do módulo vetorial, em hexadecimal.

uso: gen_vectors.py alu N QTD ARQUIVO    (N = 8: todos os pares; senão amostra com bordas)
     gen_vectors.py vec SEW QTD ARQUIVO
"""
import random
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import takum_oracle as o


def interesting(n):
    """Padrões de borda: zero, NaR, menor/maior, perto de 1, de cada regime, vizinhos."""
    s = {0, o.nar(n), 1, (1 << (n - 1)) - 1, (1 << n) - 1, o.nar(n) + 1, o.nar(n) - 1}
    for r in range(8):
        for d in (0, 1):
            for br in (r, 7 - r):
                top = (d << (n - 2)) | (br << (n - 5))
                for low in (0, 1, (1 << (n - 5)) - 1, 1 << (n - 6)):
                    for sg in (0, 1 << (n - 1)):
                        v = (sg | top | low) & ((1 << n) - 1)
                        s.add(v)
                        s.add((-v) & ((1 << n) - 1))
    for k in (1.0, 2.0, 0.5, 3.0, 0.25):
        s.add(o.encode(__import__("fractions").Fraction(k), n))
    return sorted(s)


def gen_alu(n, count, out):
    rng = random.Random(2026)
    pairs = []
    if n == 8:
        pairs = [(a, b) for a in range(256) for b in range(256)]
    else:
        edge = interesting(n)
        pairs = [(a, b) for a in edge[::max(1, len(edge) // 90)] for b in edge[::max(1, len(edge) // 90)]]
        top = 1 << n
        for _ in range(count):
            a = rng.randrange(top)
            kind = rng.random()
            if kind < 0.25:                      # b = vizinho de a (cancelamento na soma)
                b = (a + rng.randint(-3, 3)) % top
            elif kind < 0.5:                     # b = -a (+- ruído)
                b = (-a + rng.randint(-2, 2)) % top
            else:
                b = rng.randrange(top)
            pairs.append((a, b))
    with open(out, "w") as f:
        for a, b in pairs:
            for op in (0, 1, 2):
                f.write(f"{a:0{(n+3)//4}x} {b:0{(n+3)//4}x} {op} {o.alu(a, b, op, n):0{(n+3)//4}x}\n")
    print(f"{out}: {len(pairs) * 3} vetores")


VLEN = 64


def gen_vec(sew, count, out):
    rng = random.Random(7 + sew)
    lanes = VLEN // sew
    edge = interesting(sew)
    with open(out, "w") as f:
        for _ in range(count):
            op = rng.randrange(3)
            vl = rng.randint(0, lanes)
            def word():
                return sum((rng.choice(edge) if rng.random() < 0.3 else rng.randrange(1 << sew)) << (i * sew)
                           for i in range(lanes))
            vs2, vs1, old = word(), word(), word()
            vd = 0
            for i in range(lanes):
                m = (1 << sew) - 1
                if i < vl:
                    vd |= o.alu((vs2 >> (i * sew)) & m, (vs1 >> (i * sew)) & m, op, sew) << (i * sew)
                else:
                    vd |= ((old >> (i * sew)) & m) << (i * sew)
            f.write(f"{vs2:016x} {vs1:016x} {old:016x} {op} {vl:x} {vd:016x}\n")
    print(f"{out}: {count} vetores")


if __name__ == "__main__":
    kind, n, count, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    (gen_alu if kind == "alu" else gen_vec)(n, count, out)
