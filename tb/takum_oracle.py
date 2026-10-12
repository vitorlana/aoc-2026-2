"""Oráculo exato do takum linear (Hunhold 2024, Def. 8), só com inteiros e Fraction.

Não compartilha código nem estratégia com o RTL: decodifica pela fórmula completa
(inclusive negativos) e codifica montando a cadeia de bits S D R C F do valor exato,
arredondando para o mais próximo, empate para o par, NA PALAVRA (mesma decisão do
takum_encoder.v) e saturando.
"""
from fractions import Fraction

def nar(n):
    return 1 << (n - 1)


def decode(t, n):
    """Padrão de n bits -> Fraction, ou None para NaR."""
    if t == 0:
        return Fraction(0)
    if t == nar(n):
        return None
    s = (t >> (n - 1)) & 1
    d = (t >> (n - 2)) & 1
    big_r = (t >> (n - 5)) & 7
    r = big_r if d else 7 - big_r
    p = n - 5 - r
    if p >= 0:
        c_bits = (t >> p) & ((1 << r) - 1)
        f = Fraction(t & ((1 << p) - 1), 1 << p) if p else Fraction(0)
    else:  # bits de C ou F que o padrão não tem valem 0 (ghost bits)
        c_bits = (t << -p) & ((1 << r) - 1)
        f = Fraction(0)
    c = (2 ** r - 1 + c_bits) if d else (-(2 ** (r + 1)) + 1 + c_bits)
    e = (-1) ** s * (c + s)
    return (Fraction(1 - 3 * s) + f) * Fraction(2) ** e


def encode(x, n):
    """Fraction (ou None = NaR) -> padrão de n bits."""
    if x is None:
        return nar(n)
    if x == 0:
        return 0
    neg = x < 0
    m = -x if neg else x
    e = m.numerator.bit_length() - m.denominator.bit_length()
    if Fraction(2) ** e > m:
        e -= 1
    maxpos, minpos = (1 << (n - 1)) - 1, 1
    if e > 254:
        w = maxpos
    elif e < -255:
        w = minpos
    else:
        f = m / Fraction(2) ** e - 1
        if e >= 0:
            d, r = 1, (e + 1).bit_length() - 1
            c_bits = e - (2 ** r - 1)
        else:
            d, r = 0, (-e).bit_length() - 1
            c_bits = e + 2 ** (r + 1) - 1
        big_r = r if d else 7 - r
        head = (d << (3 + r)) | (big_r << r) | c_bits      # D R C, com S = 0 na frente
        scaled = (head + f) * Fraction(2) ** (n - 5 - r)   # em unidades do último bit
        w = scaled.numerator // scaled.denominator
        rem = scaled - w
        if rem > Fraction(1, 2) or (rem == Fraction(1, 2) and w & 1):
            w += 1
        if w >= 1 << (n - 1):
            w = maxpos
        elif w == 0:
            w = minpos
    return (-w) & ((1 << n) - 1) if neg else w


OPS = {0: lambda a, b: a + b, 1: lambda a, b: a - b, 2: lambda a, b: a * b}


def alu(a, b, op, n):
    """Resultado esperado de a (op) b: add, sub ou mul, tudo exato até o arredondamento."""
    x, y = decode(a, n), decode(b, n)
    if x is None or y is None:
        return nar(n)
    return encode(OPS[op](x, y), n)
