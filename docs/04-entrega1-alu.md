# Entrega 1 — ALU takum e instruções vetoriais `vtadd.vv`, `vtsub.vv`, `vtmul.vv`

**Projeto Integrador AOC 2026/02 — Zvtakum**

Escopo da guideline para as semanas 3–4: *"Implementação da ALU e das instruções aritméticas básicas (T8/T16/T32)"*.
Este documento descreve a ALU (`rtl/takum_alu.v`), a unidade vetorial (`rtl/takum_vec_alu.v`) e como foram verificadas.
O decodificador e o codificador estão em [`03-fase1-implementacao.md`](03-fase1-implementacao.md).

## 1. Arquivos novos

```
rtl/takum_alu.v       ALU combinacional: soma, subtração e multiplicação, parametrizada por N
rtl/takum_vec_alu.v   unidade vetorial: SEW = 8/16/32, vl, cauda inalterada
tb/takum_oracle.py    oráculo exato (Fraction), independente do RTL
tb/gen_vectors.py     gera os vetores de teste a partir do oráculo
tb/tb_alu.v           compara a ALU com os vetores
tb/tb_vec.v           compara a unidade vetorial com os vetores
tb/ycells.awk         lê a contagem de células da saída do Yosys
```

## 2. Decisões de projeto

| Decisão | Escolha | Motivo |
|---|---|---|
| Variante | Takum **linear** (Def. 8 de Hunhold, 2024) | A guideline fala em S, D, R, C, F; soma e produto operam em significandos lineares, como numa FPU. |
| Arquitetura | `decoder → núcleo → encoder`, combinacional | Reaproveita os módulos já testados; o núcleo só trata sinal, expoente e significando. |
| Arredondamento | Vizinho mais próximo, empate para o par, **na palavra** | Mesma regra do `takum_encoder` (Alg. 1 do artigo). |
| Saturação | Resultado finito não nulo nunca vira 0 nem NaR | Idem; o encoder satura. |
| NaR | Absorvente: `NaR op x = NaR`, inclusive `0 × NaR` | Convenção do artigo (Def. 7). |
| Subtração | `a − b = a + (−b)`: inverte o sinal de `b` | Negar o padrão em complemento de dois nega o valor (Prop. 6). |
| Zero | `a + 0 = a`; `x − x = +0`; `0 × x = 0` | Zero não tem expoente: é tratado fora do núcleo. |

## 3. Núcleo aritmético

Entradas já decodificadas: sinal, expoente `e` (9 bits com sinal), fração alinhada à esquerda (`N−5` bits).
O significando é `{1, frac}` com `W = N−4` bits.

**Multiplicação.** `sinal = sa ^ sb`, `exp = ea + eb`, `prod = ma × mb` (2W bits). Se `prod ≥ 2` (bit mais alto
ligado), soma 1 ao expoente; senão desloca 1 à esquerda. Os `N−3` bits seguintes ao bit implícito vão ao encoder
como `frac` (fração + guard + round) e o OU dos restantes vira `sticky`.

**Soma e subtração.**

1. Ordena os operandos por magnitude, comparando `{expoente, fração}` (o MSB do expoente é invertido para
   comparar números com sinal como inteiros sem sinal).
2. Alinha o menor deslocando `ea − eb` posições à direita, com 3 bits extras (guard, round, sticky); tudo o que
   sai do alinhamento é reduzido por OU num único bit sticky (*jamming*).
3. Soma (sinais iguais) ou subtrai (sinais diferentes) as magnitudes, em `N` bits.
4. Normaliza com um contador de zeros à esquerda; o expoente vira `e_maior + 1 − lz`.
5. Entrega ao encoder `N−3` bits e um sticky. Soma zero (`x − x`) vira zero positivo.

Como o sticky só é não nulo quando a distância de alinhamento é grande, e nesse caso a subtração cancela no
máximo 1 bit, 3 bits extras bastam para o resultado ser o arredondamento correto do valor exato.

## 4. Unidade vetorial

```
vd[i] = vs2[i] (op) vs1[i]    para i < vl
vd[i] = vd_old[i]             para i ≥ vl
```

| Sinal | Valores |
|---|---|
| `sew` | `0` = 8 bits, `1` = 16 bits, `2` = 32 bits |
| `op` | `0` = `vtadd.vv`, `1` = `vtsub.vv` (`vs2 − vs1`), `2` = `vtmul.vv` |
| `vl` | número de elementos ativos |

`VLEN` é parâmetro (64 por padrão). Elemento 0 fica nos bits menos significativos. Há uma fileira de ALUs por
largura e um multiplexador por `sew`; é a forma mais simples, não a menor. Máscaras (`v0.t`), `LMUL` e CSRs
ficam para a integração com o modelo RVV (semanas 5–6).

## 5. Verificação

O oráculo (`tb/takum_oracle.py`) decodifica pela fórmula completa do artigo (inclusive negativos) e codifica
montando a cadeia `S D R C F` do valor exato em `Fraction`, arredondando e saturando. Não compartilha código
nem método com o RTL. Foi validado sozinho: ida e volta exaustiva em T8 e T16, monotonicidade e `1 + 2 = 3`.

| Teste | Cobertura |
|---|---|
| ALU T8 | **todos os 65 536 pares × 3 operações** (196 608 vetores) |
| ALU T16 e T32 | ~110 mil vetores cada: bordas de cada regime, vizinhos (cancelamento), `b ≈ −a` e aleatórios |
| Vetorial, SEW 8, 16, 32 | 5 000 vetores cada, com `vl` aleatório e conferência da cauda |

**Os testes pegam erros de verdade?** Cinco defeitos introduzidos de propósito numa cópia da ALU foram todos detectados:

| Defeito introduzido | Divergências |
|---|---|
| sem sticky no alinhamento da soma | 84 (T16), 99 (T32) |
| sem sticky na multiplicação | 427 (T16) |
| sem normalizar o produto | 3 200 (T8) |
| comparação de magnitude sem tratar o sinal do expoente | 64 512 (T8) |
| subtração com NaR/zero sem negar `b` | 254 (T8) |

Rodar: `make test` (todos), `make alu`, `make vec`. Mais vetores: `make test NALU=200000 NVEC=50000`.

## 6. Custo (Yosys 0.69, síntese genérica `synth -flatten`)

| Módulo | Tamanho | Células | LUT6 |
|---|---|---|---|
| `takum_alu` | T8 | 1 001 | 327 |
| `takum_alu` | T16 | 2 342 | 912 |
| `takum_alu` | T32 | 7 536 | 2 838 |
| `takum_decoder` | T8 / T16 / T32 | 134 / 229 / 369 | 46 / 89 / 164 |
| `takum_encoder` | T8 / T16 / T32 | 217 / 329 / 518 | 69 / 112 / 209 |
| `takum_hdr_dec` | 12 bits (qualquer N) | 109 | 41 |

Os números são de síntese genérica, sem tecnologia alvo: servem para comparar tamanhos entre si, não para área
absoluta. Em T32 o multiplicador `28×28` domina. As contagens das tabelas de `03-fase1-implementacao.md` foram
feitas com Yosys 0.33 e diferem das daqui por causa da versão da ferramenta.

## 7. Limitações e próximos passos

- Combinacional, sem pipeline.
- T16 e T32 não são exaustivos (o espaço de pares é 2³² e 2⁶⁴); a cobertura é amostral com foco em bordas.
- Falta `vtdot.vv` (produto escalar com acúmulo em precisão ampliada) e `vncvt.t.t` (redução de largura), da Fase 2.
- Falta integrar as instruções ao modelo de simulação RVV e comparar a área com uma ALU IEEE 754 (Fase 3).
