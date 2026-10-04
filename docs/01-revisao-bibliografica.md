# Fase 1 — Revisão Bibliográfica

**Projeto Integrador AOC 2026/02 — Formato aritmético Takum na Extensão Vetorial RISC-V (RVV)**

> **Para quem é este documento.** Para quem estudou sistemas digitais há algum tempo
> (portas lógicas, somadores, complemento de dois, registradores) e programa, mas
> nunca estudou a fundo como o computador representa números reais.
> A ideia é sair daqui sabendo **o que** o projeto pede, **por que** o takum existe
> e **como** ele se compara com o que já existe (IEEE 754, bfloat16, FP8, posits).
>
> Os números que aparecem nos exemplos foram conferidos com um modelo de referência
> em Python (está na [Seção 8.8](#88-modelo-de-referência-em-python)).

---

## Sumário

0. [O que o projeto pede (o mapa)](#0-o-que-o-projeto-pede-o-mapa)
1. [Revisão rápida: binário, complemento de dois e ponto fixo](#1-revisão-rápida-binário-complemento-de-dois-e-ponto-fixo)
2. [Conceitos que vão aparecer em todo lugar](#2-conceitos-que-vão-aparecer-em-todo-lugar)
3. [Ponto flutuante IEEE 754](#3-ponto-flutuante-ieee-754)
4. [Os formatos "baratos" para IA: bfloat16, TF32 e FP8 (OFP8)](#4-os-formatos-baratos-para-ia-bfloat16-tf32-e-fp8-ofp8)
5. [O que há de errado com o IEEE 754? (critérios de Gustafson)](#5-o-que-há-de-errado-com-o-ieee-754-critérios-de-gustafson)
6. [Precisão afunilada (*tapered precision*)](#6-precisão-afunilada-tapered-precision)
7. [Posits](#7-posits)
8. [Takum — o formato do projeto](#8-takum--o-formato-do-projeto)
9. [Como fazer aritmética (soma e multiplicação)](#9-como-fazer-aritmética-soma-e-multiplicação)
10. [Comparação geral entre os formatos](#10-comparação-geral-entre-os-formatos)
11. [SIMD, vetores e o estudo de caso AVX10.2](#11-simd-vetores-e-o-estudo-de-caso-avx102)
12. [RISC-V e a Extensão Vetorial (RVV)](#12-risc-v-e-a-extensão-vetorial-rvv)
13. [Como o projeto será avaliado: SpMV, erro relativo e Float128](#13-como-o-projeto-será-avaliado-spmv-erro-relativo-e-float128)
14. [O que levar desta revisão para as próximas fases](#14-o-que-levar-desta-revisão-para-as-próximas-fases)
15. [Glossário](#15-glossário)
16. [Referências](#16-referências)

---

## 0. O que o projeto pede (o mapa)

O enunciado (`ProjectGuidelinesAOC.pdf`) tem três fases:

| Fase | O que é | O que você precisa saber (e onde está neste documento) |
|---|---|---|
| **1 — Módulo Takum** | Decodificar um takum em seus campos **S, D, R, C, F** e implementar **soma/subtração e multiplicação** para **T8, T16, T32** | Ponto flutuante (§3), takum (§8), aritmética (§9) |
| **2 — Extensão da ISA** | Criar instruções vetoriais `vtadd.vv`, `vtsub.vv`, `vtmul.vv`, `vtdot.vv`, `vncvt.t.t` (proposta "Zvtakum") equivalentes às de ponto flutuante da RVV | SIMD (§11), RVV (§12) |
| **3 — Avaliação** | Rodar `y = A·x` com matrizes esparsas em Takum e em IEEE 754 (FP8, FP16, FP32), medir o erro relativo contra **Float128** e analisar a redução de instruções e de **CSRs** | Avaliação (§13), comparação (§10) |

A tese do projeto, em uma frase:

> **Um único formato (takum), com um único decodificador, consegue substituir a
> "sopa de formatos" (FP16, bfloat16, E4M3, E5M2, FP32…) que as ISAs vetoriais
> foram acumulando — com menos instruções, menos casos especiais e erro igual ou menor.**

Essa tese vem de dois trabalhos de Laslo Hunhold que estão na pasta `papers/`:

- **[2]** *Beating Posits at Their Own Game: Takum Arithmetic* (`papers/2404.18603v2.pdf`) — define o takum e prova suas propriedades.
- **[1]** *Streamlining SIMD ISA Extensions with Takum Arithmetic: A Case Study on Intel AVX10.2* (`papers/2503.14067v2.pdf`) — mostra que trocar os formatos do AVX10.2 por takum simplifica a ISA. **Nosso projeto é, essencialmente, refazer esse estudo para a RVV.**

---

## 1. Revisão rápida: binário, complemento de dois e ponto fixo

### 1.1 Inteiro sem sinal

Uma palavra de *n* bits `b(n-1) … b1 b0` vale `Σ bi·2^i`. Com 8 bits: 0 a 255.

### 1.2 Complemento de dois (inteiro com sinal)

O bit mais significativo (MSB) "vale" `-2^(n-1)`. Com 8 bits: −128 a +127.

- **Negar** um número = inverter todos os bits e somar 1.
- Existe **um só zero** (`00000000`).
- O padrão `10000000` (−128) é "especial": não tem simétrico positivo.
- **Comparar** dois números é só usar o comparador de inteiros com sinal.

Guarde essas três propriedades — **o takum foi desenhado para herdá-las.**
O padrão `1000…0` vira o "não-é-um-número" (NaR) e a negação de um takum é
literalmente a negação em complemento de dois.

### 1.3 Ponto fixo

Ponto fixo é um inteiro com uma vírgula "imaginária" numa posição fixa.
Ex.: formato Q4.4 (4 bits inteiros, 4 fracionários): `0011.1000` = 3,5.

- **Vantagem:** a soma é uma soma de inteiros; hardware simples.
- **Problema:** a *faixa* é minúscula. Com 8 bits em Q4.4 você vai de 1/16 a ~8.
  Se você precisa representar 0,000001 **e** 1.000.000 ao mesmo tempo, ponto fixo não serve.

É por isso que existe **ponto flutuante**: a vírgula "flutua" de acordo com o tamanho do número.

---

## 2. Conceitos que vão aparecer em todo lugar

### 2.1 Notação científica = ponto flutuante

Ponto flutuante é a notação científica em base 2:

```
   decimal:   −6,02 × 10^23
   binário:   (−1)^sinal × 1,xxxxx × 2^expoente
                 │           │          │
               sinal    significando   expoente
```

Os três "ingredientes" de qualquer formato que veremos:

| Termo | O que é |
|---|---|
| **Sinal** | 1 bit: positivo ou negativo |
| **Expoente** | Diz "quão grande" é o número (onde fica a vírgula) |
| **Fração / mantissa** | Os dígitos significativos depois do "1," |
| **Significando** | `1 + fração` (o número inteiro "1,xxxx") |

> Os termos *característica* e *mantissa* vêm das tábuas de logaritmo (parte inteira e
> parte fracionária de um logaritmo). Por isso o takum — que é logarítmico na sua versão
> padrão — usa **C** (característica) e **M** (mantissa) no lugar de **E** e **F** [2, §4.3].
> No enunciado do projeto aparece **F** porque é o nome usado no takum **linear** (§8.6).

### 2.2 Faixa dinâmica (*dynamic range*)

É o intervalo entre o **menor** e o **maior** valor positivo representável.
Ex.: FP16 vai de ~6×10⁻⁸ a 65.504. Se uma conta gera 100.000, o FP16 **estoura**.

### 2.3 Precisão

Quantos bits significativos você tem. Mais bits de fração ⇒ números mais "próximos" uns dos outros ⇒ menos erro ao arredondar.

- **Precisão uniforme** (IEEE 754): todo número normal tem o **mesmo** número de bits de fração.
- **Precisão afunilada** (posit, takum): números perto de 1 têm **mais** bits de fração; números muito grandes ou muito pequenos têm **menos** (§6).

O dilema de qualquer formato com *n* bits fixos é:

```
   bits do expoente  ↑  ⇒  faixa ↑  e  precisão ↓
   bits da fração    ↑  ⇒  precisão ↑  e  faixa ↓
```

Esse é **exatamente** o motivo de existirem E4M3 e E5M2, FP16 e bfloat16: são escolhas
diferentes da mesma troca. O takum tenta sair desse dilema (§8).

### 2.4 Erro absoluto, erro relativo, ULP e épsilon de máquina

- **Erro absoluto:** `|x − x̃|` (x = valor exato, x̃ = valor representado).
- **Erro relativo:** `|x − x̃| / |x|`. É o que importa em ponto flutuante,
  porque errar por 1 em 1.000.000 é ótimo, mas errar por 1 em 2 é péssimo.
- **ULP** (*unit in the last place*): a distância entre dois números representáveis vizinhos.
- **Épsilon de máquina:** com *p* bits de fração e arredondamento para o mais próximo,
  o erro relativo máximo é ≈ `2^−(p+1)`. Ex.: FP32 (p = 23) ⇒ ~6×10⁻⁸ ⇒ ~7 dígitos decimais.

> Precisão em "dígitos decimais" ≈ `(p+1) × log10(2) ≈ 0,3 × (p+1)`.
> FP16 (p=10) ≈ 3,3 dígitos; bfloat16 (p=7) ≈ 2,4 dígitos; FP8 E4M3 (p=3) ≈ 1,2 dígito.

### 2.5 Arredondamento

Quase nunca o resultado exato de uma conta cabe no formato. É preciso **arredondar**.
O modo padrão (e quase universal) é **arredondar para o mais próximo, empate para o par**
(*round to nearest, ties to even* — RNE). Em hardware usam-se três bits extras abaixo do
último bit guardado: **guard**, **round** e **sticky** (o sticky é o "OU" de todos os bits
que sobraram). Você vai precisar disso na Fase 1.

### 2.6 Overflow, underflow e saturação

- **Overflow:** o resultado é maior que o maior número representável.
  No IEEE 754 ele vira **±∞**.
- **Underflow:** o resultado é menor (em módulo) que o menor representável. Vira **0** (ou subnormal).
- **Saturação:** em vez de virar ∞ ou 0, o resultado é "grampeado" no maior/menor
  número representável. **Posits e takums usam saturação** [2, §4.2]: nunca viram 0 nem ∞
  por causa de estouro. A justificativa: o erro da saturação é finito, o do overflow para ∞ é infinito.

---

## 3. Ponto flutuante IEEE 754

O IEEE 754 (versão atual: 2019, `papers/IEEE Standard 754-2019.pdf` [3]) é o padrão usado
em praticamente todo processador desde os anos 80. As instruções `vfadd.vv`, `vfmul.vv` etc.
da RVV operam em IEEE 754.

### 3.1 Formato

```
   ┌───┬────────────────┬───────────────────────────┐
   │ S │  E (ne bits)   │      F (nf bits)          │
   └───┴────────────────┴───────────────────────────┘
    1        expoente              fração
```

- **S:** sinal.
- **E:** expoente **com viés** (*bias*). Guarda-se `E = e + bias`, com `bias = 2^(ne−1) − 1`.
  Assim o expoente fica sempre como inteiro sem sinal.
- **F:** fração. O "1," inicial não é guardado (**bit implícito**).

Valor de um número **normal** (`0 < E < máximo`):

```
   valor = (−1)^S × 1,F × 2^(E − bias)
```

### 3.2 Casos especiais (é aqui que a complexidade mora)

| E | F | Significado |
|---|---|---|
| 0 | 0 | **±0** (existem dois zeros: +0 e −0) |
| 0 | ≠ 0 | **Subnormal**: `(−1)^S × 0,F × 2^(1 − bias)` (sem o 1 implícito; preenche o "buraco" perto de zero) |
| todos 1 | 0 | **±∞** |
| todos 1 | ≠ 0 | **NaN** (*Not a Number*) — existem **milhares/milhões** de padrões de NaN diferentes |
| demais | qualquer | Normal |

### 3.3 Exemplo: 1,0 em FP16

FP16: 1 bit de sinal, 5 de expoente (bias = 15), 10 de fração.

```
   1,0 = 1,0 × 2^0  ⇒  E = 0 + 15 = 15 = 01111,  F = 0
   bits:  0 01111 0000000000  = 0x3C00
```

### 3.4 Formatos padronizados

| Nome | Bits | ne | nf | bias | Menor positivo (subnormal) | Menor normal | Maior |
|---|---|---|---|---|---|---|---|
| binary16 (**FP16**, *half*) | 16 | 5 | 10 | 15 | ≈ 6,0×10⁻⁸ | ≈ 6,1×10⁻⁵ | 65.504 |
| binary32 (**FP32**, *single*) | 32 | 8 | 23 | 127 | ≈ 1,4×10⁻⁴⁵ | ≈ 1,2×10⁻³⁸ | ≈ 3,4×10³⁸ |
| binary64 (**FP64**, *double*) | 64 | 11 | 52 | 1023 | ≈ 4,9×10⁻³²⁴ | ≈ 2,2×10⁻³⁰⁸ | ≈ 1,8×10³⁰⁸ |
| binary128 (**Float128**, *quad*) | 128 | 15 | 112 | 16383 | ≈ 6,5×10⁻⁴⁹⁶⁶ | — | ≈ 1,2×10⁴⁹³² |

> O **Float128** é o que o projeto usa como "valor verdadeiro" para medir o erro (§13):
> com 112 bits de fração, o erro dele é desprezível perto dos formatos de 8–32 bits.

### 3.5 Modos de arredondamento e exceções (estado!)

O IEEE 754 exige [3, §4.3 e §7]:

- **5 modos de arredondamento:** para o mais próximo/empate par (padrão), para o mais
  próximo/empate longe do zero, em direção a +∞, em direção a −∞, em direção a zero.
- **5 exceções**, sinalizadas por *flags* "grudentas" que o software pode ler depois:
  **invalid** (ex.: 0/0, √−1), **divideByZero**, **overflow**, **underflow**, **inexact**.

No RISC-V isso vira **estado no processador**: o CSR `fcsr` guarda o modo de arredondamento
(`frm`, 3 bits) e as flags (`fflags`, 5 bits). Toda instrução de ponto flutuante — escalar
**ou vetorial** — lê `frm` e atualiza `fflags`. Isso é importante para a Fase 3 (§12.5).

---

## 4. Os formatos "baratos" para IA: bfloat16, TF32 e FP8 (OFP8)

Redes neurais toleram pouca precisão, mas precisam de **faixa**: gradientes podem ser
minúsculos e ativações grandes. O FP16 tem pouca faixa (máximo 65.504), então a indústria
criou variações do IEEE 754 que só mudam quantos bits vão para o expoente e para a fração:

| Formato | Bits | ne | nf | Maior | Menor normal | Observações |
|---|---|---|---|---|---|---|
| **FP16** | 16 | 5 | 10 | 65.504 | ≈ 6,1×10⁻⁵ | Padrão IEEE |
| **bfloat16** (Google, "brain float") | 16 | 8 | 7 | ≈ 3,4×10³⁸ | ≈ 1,2×10⁻³⁸ | = os 16 bits de cima do FP32. Mesma faixa do FP32, pouca precisão. Frequentemente sem subnormais |
| **TF32** (NVIDIA) | 19 | 8 | 10 | ≈ 3,4×10³⁸ | ≈ 1,2×10⁻³⁸ | Formato interno de tensor cores |
| **OFP8 E4M3** | 8 | 4 | 3 | 448 | 2⁻⁶ ≈ 0,0156 | Sem ∞; só um NaN por sinal (`S.1111.111`) |
| **OFP8 E5M2** | 8 | 5 | 2 | 57.344 | 2⁻¹⁴ ≈ 6,1×10⁻⁵ | Tem ∞ e NaN como o IEEE |

("OFP8" = *OCP 8-bit Floating Point*, especificação do Open Compute Project.)

Repare: **E4M3 e E5M2 são duas apostas opostas na mesma troca precisão × faixa**, e o mesmo
vale para FP16 × bfloat16. Cada uma delas exige, no processador:

- instruções de conversão próprias (de/para FP16, FP32, inteiros…);
- regras próprias de casos especiais (E4M3 não tem ∞, E5M2 tem);
- às vezes instruções "especiais" (o AVX10.2 tem conversões com viés só para FP8 e
  divisões "sem exceção" só para bfloat16 [1, §III]).

Esse é o problema que o artigo [1] chama de **fragmentação** da ISA.

---

## 5. O que há de errado com o IEEE 754? (critérios de Gustafson)

John Gustafson (criador dos posits) propôs 10 critérios para um "bom" sistema numérico.
Hunhold os usa como régua [2, §1.1]:

| # | Critério | O que significa | IEEE 754 cumpre? |
|---|---|---|---|
| 1 | **Distribuição** | Os números representáveis devem estar onde os cálculos acontecem; todo padrão de bits deve ser útil | ✗ — FP64 "gasta" ~82% dos padrões em magnitudes que quase ninguém usa (> 10⁵⁵ ou < 10⁻⁵⁵); FP16/FP32 têm faixa curta demais |
| 2 | **Unicidade** | Um valor ⇔ um padrão de bits | ✗ — dois zeros (+0/−0) e muitos NaNs (~5% dos padrões de um float8 com 4 bits de expoente, ~3% do FP16) |
| 3 | **Generalidade** | Definido para qualquer número de bits | ✗ — cada tamanho tem parâmetros próprios (ne, nf) escolhidos "à mão" |
| 4 | **Sem estado** | O resultado depende só das entradas | ✗ — depende do modo de arredondamento e gera flags |
| 5 | **Exatidão** | Operações não devem errar mais que a precisão do formato | parcial |
| 6 | **Monotonicidade binária** | Se eu ler os bits como inteiro com sinal (complemento de 2), a ordem dos inteiros = ordem dos reais | ✗ — o IEEE usa sinal-magnitude: negativos estão "ao contrário" |
| 7 | **Negação binária** | Negar em complemento de 2 = negar o real | ✗ — nega-se trocando o bit de sinal |
| 8 | **Flexibilidade** | Converter entre tamanhos deve ser fácil | ✗ — muda o bias e o tamanho do expoente |
| 9 | **Propagação de NaR** | Um "não-real" deve contaminar todo resultado posterior | ✗ — ex.: `pow(NaN, 0) = 1` |
| 10 | **Implementação simples** | Pouco hardware, pouca energia, baixa latência | ✗ — subnormais, NaNs, ±0, ∞ e flags custam hardware |

Por que 6 e 7 importam **para o hardware**: se o formato se ordena como inteiro com sinal,
o comparador (`<`, `max`, `min`) e o negador são **o mesmo hardware da ALU de inteiros**.
O artigo [1, §IV-A] chega a sugerir que a distinção entre registradores/instruções "de inteiro"
e "de ponto flutuante" para comparações deixaria de ser necessária.

---

## 6. Precisão afunilada (*tapered precision*)

Ideia: **os números que mais aparecem em cálculos estão perto de 1** (em módulo).
Então vale a pena dar **mais bits de fração** para eles e **menos** para os números
gigantes ou minúsculos, que aparecem pouco.

```
 bits de fração
   ▲
   │          IEEE 754 (uniforme): ──────────────── (mesma precisão em toda a faixa,
   │                                                  e de repente acaba)
   │              ╱‾‾‾‾╲
   │            ╱        ╲     afunilado (posit/takum): muita precisão perto de 1,
   │         ╱              ╲  pouca nas pontas, mas faixa bem maior
   │     ╱                      ╲
   └──────────────────┼────────────────────────► log |x|
                      1
```

Para isso, o **tamanho do campo de expoente passa a ser variável**: números perto de 1 usam
poucos bits de expoente (sobrando bits para a fração); números distantes usam mais.

Dois termos do livro *Every Bit Counts* [4]:

- **Fóvea:** a região (perto de 1) em que o formato tem o número máximo de bits de fração
  (o nome vem da região da retina com maior resolução).
- **Zona Dourada (*Golden Zone*):** a região em que o formato é **pelo menos tão preciso**
  quanto o IEEE 754 de mesmo tamanho. Para o posit32, é de 2⁻²⁰ a 2²⁰ (~10⁻⁶ a 10⁶) [4, §13.4.1].

O preço do afunilamento: **o número de bits de fração depende do valor**. Para descobri-lo,
o hardware precisa primeiro decodificar o campo de expoente de tamanho variável.
A **diferença fundamental entre posit e takum é como esse campo de tamanho variável é codificado.**

---

## 7. Posits

Posits foram criados por Gustafson e Yonemoto (2017) e têm um padrão de 2022
(`papers/posit_standard-2.pdf` [5]). O livro *Every Bit Counts: Posit Computing* [4]
(`papers/Every Bit Counts…`) é a referência didática.

### 7.1 Formato

```
   ┌───┬───────────────────────┬────┬──────────────┐
   │ S │ R R R … R  R̄          │ E E│  F F F … F   │
   └───┴───────────────────────┴────┴──────────────┘
    1    regime (k+1 bits)       2     fração (o que sobrar)
```

- **S:** sinal.
- **Regime:** uma sequência de *k* bits **iguais**, terminada por um bit **diferente** (código unário,
  como contar com risquinhos). Se os bits são `1`, o regime vale `r = k − 1`; se são `0`, vale `r = −k`.
  Cada unidade de regime multiplica o número por **16** (2⁴).
- **E:** 2 bits de expoente (es = 2 no padrão de 2022), valor 0 a 3.
- **F:** a fração — **o que sobrar**. Se o regime é longo, a fração encolhe ou some.
- Bits que "caíram para fora" do final são considerados 0 (*ghost bits*, bits-fantasma).

Valor (para positivos): `(1 + f) × 2^(4r + e)`. Negativos: complemento de 2 do padrão inteiro.

Casos especiais — **só dois**:

- `000…0` = **0** (um só zero).
- `100…0` = **NaR** (*Not a Real*) — o único "não-número". Substitui NaN **e** ∞.

### 7.2 Exemplos com posit8

| Bits | Regime | E | Valor |
|---|---|---|---|
| `0 10 00 000` | `10` → r = 0 | 00 | 1 |
| `0 10 01 000` | `10` → r = 0 | 01 | 2 |
| `0 10 10 000` | `10` → r = 0 | 10 | 4 |
| `0 110 00 00` | `110` → r = 1 | 00 | 16 |
| `0 1110 000` | `1110` → r = 2 | 00 | 256 |
| `0 1111111` | `1111111` → r = 6 | (fantasma) | 2²⁴ ≈ 1,7×10⁷ (maior posit8) |
| `1 10 00 000` | (complemento de 2 de 1) | | −1 |

### 7.3 Vantagens dos posits

- Um zero, um NaR; sem subnormais; sem ∞; **sem flags e um só modo de arredondamento** (o padrão
  diz explicitamente que exceções não implicam *flags* de status [5, §2]).
- Ordem = ordem de inteiro com sinal; negação = complemento de 2 (critérios 6 e 7).
- **Quire:** um acumulador de ponto fixo enorme (16·n bits) que soma produtos **sem nenhum
  arredondamento** até ~2³¹ termos [5, §3.2]. Ideal para produto escalar — compare com a
  instrução `vtdot.vv` do projeto, que pede "acúmulo em precisão ampliada".

### 7.4 Problemas dos posits (que motivaram o takum)

1. **O regime em unário é caro longe de 1.** Para representar um número grande, o regime
   come quase todos os bits. Um posit32 perto de 10³⁶ não tem fração nenhuma.
2. **Faixa curta em poucos bits:** posit8 vai só de 6×10⁻⁸ a 1,7×10⁷; posit16 de 10⁻¹⁷ a 7×10¹⁶.
   Constantes físicas como a de Planck (6,6×10⁻³⁴) **não cabem** num posit16 [2, Tab. 5].
3. **Decodificador caro:** o regime pode ocupar **o número inteiro**. O hardware precisa de um
   contador de zeros/uns à esquerda (LZC) do tamanho da palavra e de um deslocador grande.
   Cada tamanho (8, 16, 32…) precisa do seu decodificador [1, §I].
4. **Faixa cresce sem parar com n:** posit64 vai a 10⁷⁴, posit256 a 10³⁰⁵ — bits gastos em
   magnitudes que ninguém usa, quando deveriam virar precisão.

---

## 8. Takum — o formato do projeto

Takum foi proposto por Laslo Hunhold em 2024 [2]. O nome vem do islandês *takmarkað umfang*,
"**faixa limitada**". A ideia central:

> **Primeiro alcance rapidamente uma faixa dinâmica "suficiente para qualquer aplicação"
> (~10⁻⁵⁵ a 10⁵⁵ na versão logarítmica, ~10⁻⁷⁷ a 10⁷⁷ na linear); depois disso, todo bit
> a mais vira precisão.** [2, §1.2], [4, §13.4.2]

Por que essa faixa? O artigo argumenta com constantes físicas: a constante cosmológica
(≈ 10⁻⁵²) e a massa do universo observável (≈ 10⁵³) ficam dentro dela, e é comum
reescalar unidades (parsec, elétron-volt) para trazer números para perto de 1 [2, §1.2].
O expoente máximo é escolhido como **255 = 2⁸ − 1** (um número cuja representação binária
"satura" 8 bits), o que permite codificá-lo com apenas **3 bits de regime**.

### 8.1 Os campos: S, D, R, C, F

```
   ┌───┬───┬─────────┬────────────────┬───────────────────────────┐
   │ S │ D │ R2 R1 R0│  C (r bits)    │    F / M  (p bits)        │
   └───┴───┴─────────┴────────────────┴───────────────────────────┘
     1   1      3       r ∈ {0…7}        p = n − 5 − r
   sinal dir. regime   característica      fração (linear) / mantissa (log)
   └──────────── no máximo 12 bits ───────┘
```

| Campo | Bits | Função |
|---|---|---|
| **S** — sinal | 1 | 0 = positivo, 1 = negativo |
| **D** — direção | 1 | 1 = \|x\| ≥ 1 (expoente ≥ 0); 0 = \|x\| < 1 (expoente < 0) — para números positivos |
| **R** — regime | 3 | Diz **quantos** bits de característica vêm a seguir: `r` de 0 a 7 |
| **C** — característica | r (0 a 7) | O expoente propriamente dito, em binário posicional |
| **F** — fração | o resto | Os bits significativos |

**Comparando com o posit:** o posit diz o tamanho do expoente em **unário** (risquinhos),
o que pode gastar a palavra inteira. O takum diz o tamanho em **binário com 3 bits fixos**,
então **o cabeçalho S+D+R+C tem no máximo 1+1+3+7 = 12 bits — sempre.**

### 8.2 As fórmulas, passo a passo (takum linear — o que o projeto implementa)

Para um takum de *n* bits (se n < 12, completa-se com zeros à direita até 12 bits — *ghost bits*):

**Passo 1 — regime:** leia R como inteiro de 3 bits.

```
   r = R          se D = 1
   r = 7 − R      se D = 0
```

**Passo 2 — característica:** leia os próximos `r` bits como inteiro sem sinal `C`.

```
   c = 2^r − 1 + C            se D = 1     → c ∈ {0, 1, …, 254}
   c = −2^(r+1) + 1 + C       se D = 0     → c ∈ {−255, …, −1}
```

Intuição para D = 1: o número `1C` (um "1" implícito na frente de C) menos 1.
Com r = 0 → c = 0; r = 1 → c ∈ {1, 2}; r = 2 → c ∈ {3…6}; … r = 7 → c ∈ {127…254}.

**Passo 3 — fração:** os `p = n − 5 − r` bits restantes, `f = F / 2^p ∈ [0, 1)`.

**Passo 4 — expoente e valor:**

```
   e = (−1)^S × (c + S)                                 (e ∈ {−255, …, 254})
   valor = [(1 − 3S) + f] × 2^e
```

Para S = 0: `valor = (1 + f) × 2^c` — idêntico a um float normal com expoente c.
Para S = 1: `valor = (−2 + f) × 2^e` — essa forma "estranha" é o que faz a negação ser
complemento de 2 (§8.4). **Truque prático:** para decodificar um negativo, faça o complemento
de 2 da palavra inteira, decodifique como positivo e troque o sinal.

**Casos especiais — só dois:** `000…0` = **0**; `100…0` = **NaR**.

### 8.3 Exemplos em T8 (8 bits; conferidos com o modelo da §8.8)

Os 8 bits são completados com 4 bits-fantasma (`0000`) para formar 12.

| Bits (S D RRR resto) | r | c | f | Valor takum8 | Mesmo padrão em posit8 |
|---|---|---|---|---|---|
| `0 1 000 000` | 0 | 0 | 0 | **1** | 1 |
| `0 1 000 001` | 0 | 0 | 1/8 | **1,125** | 1,125 |
| `0 1 001 000` | 1 | 1 | 0 | **2** | 2 |
| `0 1 010 000` | 2 | 3 | 0 | **8** | 4 |
| `0 1 100 000` | 4 | 15 | 0 | **2¹⁵ = 32.768** | 16 |
| `0 0 111 111` | 0 | −1 | 7/8 | **0,9375** | 0,9375 |
| `0 0 100 000` | 3 | −15 | 0 | **2⁻¹⁵ ≈ 3,05×10⁻⁵** | — |
| `0 1 111 111` | 7 | 239 | 0 | **2²³⁹ ≈ 8,8×10⁷¹** (maior T8) | 2²⁴ ≈ 1,7×10⁷ |
| `0 0 000 001` | 7 | −239 | 0 | **2⁻²³⁹ ≈ 1,1×10⁻⁷²** (menor T8) | 2⁻²⁴ ≈ 6×10⁻⁸ |
| `1 1 000 000` | 0 | 0 | 0 | **−1** | −1 |
| `1 0 111 111` | 0 | — | — | **−1,125** | −1,125 |

Detalhe do maior T8 (`0 1 111 111`): R = 111 → r = 7 bits de característica; só há 3 explícitos
(`111`), os outros 4 são fantasmas (`0000`) ⇒ C = `1110000` = 112 ⇒ c = 2⁷ − 1 + 112 = 239.
O livro faz exatamente esta conta [4, §13.4.2].

**Repare na última coluna:** perto de 1 os dois formatos coincidem; longe de 1 o takum8 alcança
2²³⁹ enquanto o posit8 para em 2²⁴. Um número de **8 bits** cobre de 10⁻⁷² a 10⁷².

### 8.4 Propriedades (todas provadas formalmente em [2, §4.5])

| Propriedade | O que garante | Por que importa no hardware |
|---|---|---|
| **Unicidade** (Prop. 3) | Cada valor tem um único padrão de bits | Nada de ±0 ou NaNs redundantes |
| **Monotonicidade** (Prop. 4) | Ordenar os bits como inteiro com sinal = ordenar os valores | `vtmin`, `vtmax`, comparações = **comparador de inteiros** |
| **Negação** (Prop. 6) | `−x` = complemento de 2 dos bits | Negação/subtração usa o negador de inteiros |
| **Inversão** (Prop. 7, só log.) | `1/x` = complemento de 2 de tudo exceto o sinal | Recíproco "de graça" na versão logarítmica |
| **Ghost bits / extensão por zeros** | Acrescentar zeros à direita não muda o valor | Converter T8 → T16 → T32 é só **concatenar zeros**; T32 → T16 é **arredondar e cortar** |
| **Decodificador comum** | O cabeçalho cabe sempre nos 12 bits de cima | **Um único decodificador** de 12 bits serve T8, T16, T32, T64 |
| **NaR = menor de todos** (Def. 7) | `100…0` é o menor inteiro com sinal | Comparações não precisam de caso especial para NaR; um laço `while (residuo < limite)` termina se aparecer NaR |
| **Saturação** (§4.2) | Nada vira 0 ou ∞ por estouro | Sem flags de overflow/underflow |

O decodificador pode ser uma **tabela de 8 entradas** indexada pelo regime: para cada `r` ela dá
uma máscara para extrair C e a posição onde começa a fração (≈ 16 bytes no total) [2, §5.2].
Compare com o posit, que precisa de um contador de bits e de um deslocador do tamanho da palavra.

### 8.5 Quantos bits de fração cada tamanho tem?

`p = n − 5 − r`, com `r` de 0 a 7:

| Formato | Bits de fração | Compare com |
|---|---|---|
| **T8** | 0 a 3 (3 perto de 1) | E4M3: 3 · E5M2: 2 |
| **T16** | 4 a 11 | FP16: 10 · bfloat16: 7 |
| **T32** | 20 a 27 | FP32: 23 |
| **T64** | 52 a 59 | FP64: 52 (T64 **nunca** tem menos fração que FP64 [2, §4.5]) |

Faixas em que o takum tem **pelo menos tanta fração** quanto o concorrente (pelas fórmulas acima):

- **T32 ≥ FP32** para 2⁻³¹ ≤ |x| < 2³¹ (≈ 4,7×10⁻¹⁰ a 2,1×10⁹), e ainda vai até ~10⁷⁷.
- **T16 ≥ FP16** para 2⁻³ ≤ |x| < 2³ (0,125 a 8); **T16 ≥ bfloat16** para 2⁻³¹ ≤ |x| < 2³¹.
- **T8 = E4M3** (3 bits) para 0,5 ≤ |x| < 2; **T8 ≥ E5M2** (2 bits) para 0,125 ≤ |x| < 8.

Fora dessas faixas o takum tem menos fração — mas os formatos IEEE pequenos simplesmente
**não representam** boa parte desses números (estouram para ∞/0).

### 8.6 Takum linear × takum logarítmico

O artigo [2] define **duas** variantes com os mesmos campos:

| | **Takum logarítmico** (padrão do artigo) | **Takum linear** |
|---|---|---|
| Valor | `(−1)^S × √e^ℓ`, com `ℓ = (−1)^S (c + m)` | `[(1 − 3S) + f] × 2^e` |
| Base | √e ≈ 1,6487 | 2 |
| Último campo se chama | **M** (mantissa) | **F** (fração) |
| Faixa | ≈ 4,2×10⁻⁵⁶ a 2,4×10⁵⁵ | ≈ 1,7×10⁻⁷⁷ a 5,8×10⁷⁶ (T8: 10^±72) |
| Multiplicação/divisão | **soma/subtração de inteiros** (ponto fixo) | como float (soma expoentes, multiplica frações) |
| Soma/subtração | difícil: precisa de **logaritmo gaussiano** (tabelas + interpolação) | como float (alinha, soma, normaliza) |
| Recíproco por bits | sim (Prop. 7) | não |
| Erro relativo máximo | ≤ ⅔ do de um float com mesma fração | igual ao de um float com mesma fração |

**Recomendação para o projeto:** implementar o **takum linear**. Motivos:

1. O enunciado usa **F** (fração) para o último campo e fala em **T8/T16/T32** como no
   artigo do AVX10.2 [1], cujos gráficos de faixa dinâmica são para o **takum linear**.
2. Soma/subtração/multiplicação reaproveitam tudo o que se sabe sobre somadores e
   multiplicadores de ponto flutuante — só **o decodificador e o codificador mudam**.
3. A soma logarítmica exige tabelas de Φ⁺(q) = log(1 + b⁻ᵍ) e interpolação, um projeto à parte.

Se o grupo quiser, pode citar a variante logarítmica como trabalho futuro ou comparar as duas.

### 8.7 Codificação (de float para takum)

Dado um positivo `(1 + g) × 2^h` com `h ∈ {−255…254}` (Algoritmo 4 de [2], para S = 0):

```
   D = (h ≥ 0)
   se D = 1:  r = ⌊log2(h + 1)⌋ ;  R = r     ;  C = h − 2^r + 1
   se D = 0:  r = ⌊log2(−h)⌋    ;  R = 7 − r ;  C = h + 2^(r+1) − 1
   bits = 0 | D | R(3 bits) | C(r bits) | fração g (o que couber em n − 5 − r bits)
   arredonde para n bits (veja abaixo)
   se o número era negativo: complemento de 2 da palavra
```

`⌊log2(h+1)⌋` em hardware é a posição do 1 mais significativo (um *priority encoder* de 8 bits).

**Arredondamento** [2, Alg. 1]: o arredondamento é feito **sobre a palavra de bits como inteiro**
(graças à monotonicidade): gera-se o padrão com 1 bit a mais, olha-se o bit extra e soma-se 1 se
for preciso. Depois aplica-se a saturação: se o resultado virou 0 sem que x seja 0, vira o menor
positivo; se virou NaR sem que x seja NaR, vira o maior. **Atenção:** o padrão posit usa
"empate para o par" com bit *sticky*; o grupo deve definir e documentar a regra de desempate
que vai implementar (recomendado: RNE sobre a palavra de bits, que é o que o padrão posit faz).

### 8.8 Modelo de referência em Python

Este é o modelo usado para conferir os exemplos deste documento. Ele **decodifica** um takum
linear de qualquer tamanho com aritmética racional exata (útil como "oráculo" nos testes da Fase 1):

```python
from fractions import Fraction

def takum_linear_decode(bits: int, n: int):
    """Decodifica um takum LINEAR de n bits. Retorna 0, 'NaR' ou um Fraction exato."""
    N = max(n, 12)
    b = bits << (N - n)                      # ghost bits: completa com zeros até 12 bits
    if b == 0:
        return 0
    if b == 1 << (N - 1):
        return 'NaR'
    S = (b >> (N - 1)) & 1
    D = (b >> (N - 2)) & 1
    R = (b >> (N - 5)) & 0b111
    r = R if D else 7 - R                    # nº de bits de característica
    C = (b >> (N - 5 - r)) & ((1 << r) - 1)
    c = (2**r - 1 + C) if D else (-2**(r + 1) + 1 + C)
    p = N - 5 - r                            # nº de bits de fração
    f = Fraction(b & ((1 << p) - 1), 2**p)
    e = (-1)**S * (c + S)
    return ((1 - 3 * S) + f) * Fraction(2)**e

# takum_linear_decode(0b01000000, 8) -> 1
# takum_linear_decode(0b01111111, 8) -> 2**239
```

Com ele verificamos, para **todos** os padrões de T8 e T16, que (a) a negação é o complemento
de 2 e (b) a ordem dos valores é a ordem dos inteiros com sinal — as Propriedades 4 e 6 da §8.4.

### 8.9 Takum logarítmico em detalhe

> A versão HTML (`docs/revisao-bibliografica.html`) tem este conteúdo com laboratórios:
> decodificador no modo logarítmico, calculadora com logaritmo gaussiano, experimento de
> produtos escalares linear × log × IEEE e um assistente de decisão.

**Ideia (LNS):** guardar o logaritmo do número em ponto fixo. Multiplicar vira somar (régua de cálculo).

```
Campos:   S | D | R | C | M          (S, D, R, C idênticos ao takum linear)
m = M / 2^p                          mantissa = parte fracionária do log
ℓ = (−1)^S × (c + m)                 valor logarítmico
x = (−1)^S × √e^ℓ                    √e ≈ 1,6487   (ℓ = 2·ln|x|)
```

| Bits (8) | ℓ | Takum log | Takum linear |
|---|---|---|---|
| `0 1 000 000` | 0 | 1 | 1 |
| `0 1 000 001` | 0,125 | ≈ 1,0645 | 1,125 |
| `0 1 001 000` | 1 | √e ≈ 1,6487 | 2 |
| `1 0 111 100` | 0,5 | −1,2840 | −1,5 |
| `0 1 111 111` | 239 | ≈ 7,9×10⁵¹ | ≈ 8,8×10⁷¹ |

- **Multiplicação/divisão:** `ℓ ± ℓ̃` (soma de ponto fixo). **1/x:** complemento de 2 de D,R,C,M (Prop. 7). **√x, x²:** deslocamentos.
- **Soma/subtração:** com `q = ℓ − ℓ̃ ≥ 0`, `ℓ_soma = ℓ + Φ⁺(q)`, `Φ⁺(q) = 2·ln(1 + e^(−q/2))`; subtração com `Φ⁻(q) = 2·ln(1 − e^(−q/2))`, que vai a −∞ perto de q = 0. Em hardware: tabelas + interpolação; viável até ~32 bits (European Logarithmic Microprocessor) [2, §4.3], [4, §8.4].
- **Precisão:** erro máximo `λ(p) = √e^(2^(−p−1)) − 1 < ⅔·2^(−p−1)`, uniforme dentro da binade [2, Prop. 11]. Um único tipo de arredondamento (média geométrica).
- **Custos:** nem o número 2 é exato (2 → 2,0004 em T16); conversão IEEE ↔ takum log exige ln/exp [2, Alg. 2–3]; quire vira "bidimensional" e caro [4, §8.5].
- **Base √e:** dá a faixa 10^±55; trocar para base e é um deslocamento; facilita ln/exp e Φ [2, §4.4].

**Linear ou log para este projeto?** As duas compartilham decodificador de 12 bits, faixa fixa, negação e comparação de inteiros. A diferença numérica entre elas em produtos escalares é pequena (o acúmulo de arredondamentos domina); a diferença grande é contra o IEEE. Por isso: **RTL → takum linear**; **simulador → linear como principal e log como comparação** (no software Φ é só `log1p`/`exp`); **log como principal** só se o grupo tiver tempo e quiser explorar LNS, planejando tabelas de Φ, conversões com ln/exp e o acumulador do `vtdot.vv`.

---

## 9. Como fazer aritmética (soma e multiplicação)

Como o takum linear tem a forma `(1 + f) × 2^e`, a Fase 1 pode ser organizada assim:

```
   takum A ──► [DECODIFICADOR] ──► (sinal, expoente e, significando 1.f) ─┐
                                                                          ├─► [NÚCLEO FP] ─► (s, e, 1.f exato/alargado) ─► [CODIFICADOR + ARREDONDA + SATURA] ─► takum
   takum B ──► [DECODIFICADOR] ──► (sinal, expoente e, significando 1.f) ─┘
```

O "núcleo FP" é o mesmo de qualquer FPU, com duas simplificações: **não há subnormais, ∞ nem
NaNs múltiplos**, e o expoente é um inteiro com sinal de 9 bits (−255…254) **igual para todos os
tamanhos**. Antes de tudo, trate os casos especiais: se uma entrada é NaR → resultado NaR;
zeros conforme a operação.

### 9.1 Multiplicação

```
   sinal  = sA XOR sB
   e      = eA + eB
   sig    = (1.fA) × (1.fB)          → resultado em [1, 4)
   se sig ≥ 2:  sig = sig / 2 ; e = e + 1     (normaliza)
   codifica (sinal, e, sig) em takum de n bits, arredondando; satura se e sair de −255…254
```

### 9.2 Soma / subtração

```
   subtração: A − B = A + (−B), e −B é só o complemento de 2 dos bits de B
   ordene para |A| ≥ |B|      (dica: compare os bits sem sinal como inteiros!)
   d = eA − eB
   alinhe: sigB = sigB >> d   (guardando guard/round/sticky)
   sinais iguais:    sig = sigA + sigB   (pode precisar de normalização à direita)
   sinais diferentes: sig = sigA − sigB  (pode precisar de normalização à esquerda: LZC)
   codifica e arredonda
```

### 9.3 Por que `vtdot.vv` pede "acúmulo em precisão ampliada"

Somar muitos produtos arredondando a cada passo acumula erro (e a ordem das somas muda o
resultado). As soluções clássicas:

- **FMA** (*fused multiply-add*): `a×b + c` com um único arredondamento.
- **Acumulador alargado**: multiplicar T8×T8 e acumular em T16 (ou T16 → T32), como o
  `VDPPT8PT16` proposto em [1, Tab. IV].
- **Quire** (posits): acumulador de ponto fixo largo, sem arredondamento nenhum até o final.

Para takum a ideia do quire é especialmente atraente porque o expoente tem faixa fixa
(−255…254) — o acumulador teria um tamanho fixo e conhecido para todos os tamanhos.

### 9.4 Aritmética no takum logarítmico (para referência)

Com `x = √e^ℓx` e `y = √e^ℓy`: `x·y = √e^(ℓx+ℓy)`, `x/y = √e^(ℓx−ℓy)`, `√x = √e^(ℓx/2)` — tudo
soma/deslocamento de inteiros. Mas `x + y = √e^(ℓx + Φ⁺(ℓx − ℓy))` com
`Φ⁺(q) = log√e(1 + √e^−q)` — uma função não-linear calculada com tabelas e interpolação [2, §4.3].
O livro [4, cap. 8 e 9] discute sistemas logarítmicos (LNS) em detalhe.

---

## 10. Comparação geral entre os formatos

### 10.1 Características

| | IEEE 754 (FP16/32) | bfloat16 / OFP8 | Posit (es=2) | **Takum (linear)** |
|---|---|---|---|---|
| Precisão | uniforme | uniforme | afunilada | afunilada |
| Tamanho do expoente | fixo | fixo | variável (regime unário) | variável (regime binário de 3 bits) |
| Zeros | +0 e −0 | +0 e −0 | 1 | 1 |
| Não-números | muitos NaN + ±∞ | NaN (E4M3 sem ∞) | 1 NaR | 1 NaR |
| Subnormais | sim | depende | não | não |
| Overflow | → ±∞ | → ±∞ / NaN / satura (depende) | satura | satura |
| Modos de arredondamento | 5 | idem | 1 | 1 |
| Flags de exceção | 5 | idem | nenhuma | nenhuma |
| Comparar = comparar inteiros | não | não | sim | sim |
| Negar = complemento de 2 | não | não | sim | sim |
| Mudar de tamanho | reconverter campos | reconverter campos | completar/cortar bits | completar/cortar bits |
| Decodificador | um por formato | um por formato | um por tamanho, olha a palavra toda | **um só, olha só 12 bits** |
| Parâmetros por tamanho | sim (ne, nf) | sim | não (só n) | não (só n) |

### 10.2 Faixa dinâmica (maior valor positivo)

| Bits | IEEE 754 | Derivados | Posit | **Takum linear** |
|---|---|---|---|---|
| 8 | — | E4M3: 448 · E5M2: 57.344 | 1,7×10⁷ | **8,8×10⁷¹** |
| 16 | FP16: 65.504 | bfloat16: 3,4×10³⁸ | 7,2×10¹⁶ | **5,6×10⁷⁶** |
| 32 | FP32: 3,4×10³⁸ | — | 1,3×10³⁶ | **5,8×10⁷⁶** |
| 64 | FP64: 1,8×10³⁰⁸ | — | 4,5×10⁷⁴ | **5,8×10⁷⁶** |

O menor positivo é sempre o inverso (aproximadamente) do maior. Note como a faixa do takum
**já está praticamente completa em 8 bits e para de crescer a partir de 12** — de 12 bits em
diante, todo bit novo vira fração.

### 10.3 Resultados experimentais de [1] (o experimento que vamos estender)

Hunhold converteu as **1.401 matrizes** da coleção SuiteSparse com até 50.000 não-zeros para cada
formato, voltou para Float128 e mediu o **erro relativo na norma 2** [1, §II, Fig. 3]:

| Tamanho | Resultado |
|---|---|
| **8 bits** | E4M3 e E5M2 erram mais de 100% em ~45% e ~55% das matrizes (estouro de faixa). Posit8: ~65% das matrizes abaixo de 100%. **Takum8: ~90% abaixo de 100%.** |
| **16 bits** | Takum16 supera FP16 e bfloat16 em toda a distribuição; posit16 erra menos no início mas é menos estável |
| **32 bits** | Takum32 supera FP32 em toda a distribuição; posit32 tem uma região pior que FP32 |

E sobre a ISA: o AVX10.2 tem **756 instruções**, das quais **363 de ponto flutuante**; trocando
todos os formatos por takum, os grupos F01–F06 viram **um único grupo**, e as conversões
(grupo F07, o mais confuso) viram uma família regular `VCVT…T(8|16|32|64)` [1, §IV-D].

> **A Fase 3 do nosso projeto é a versão RVV desse experimento**, com um passo a mais:
> em vez de só converter a matriz, **executamos** `y = A·x` com as instruções vetoriais.

---

## 11. SIMD, vetores e o estudo de caso AVX10.2

### 11.1 SIMD

**SIMD** (*Single Instruction, Multiple Data*, taxonomia de Flynn): uma instrução opera sobre
vários dados de uma vez. Um registrador de 512 bits pode guardar 64 × T8, 32 × T16 ou 16 × T32,
e `vtadd` soma todos os pares **em paralelo** (uma "pista" — *lane* — por elemento).

**Por que formatos pequenos importam tanto aqui:** com o mesmo registrador e a mesma banda de
memória, 8 bits processam **4× mais elementos** que 32 bits. Hoje o gargalo costuma ser mover
dados (a "**parede de memória**", *memory wall*), não calcular — por isso [1, §V] destaca os
formatos de 8 e 16 bits.

### 11.2 SIMD "empacotado" × vetorial

- **SIMD empacotado (x86 SSE/AVX, ARM NEON):** o tamanho do registrador está **no opcode**
  (`xmm` = 128 bits, `ymm` = 256, `zmm` = 512). Cada nova largura gerou novas instruções.
- **ISA vetorial (RISC-V V, ARM SVE):** o código é **independente do tamanho do registrador**
  (*vector-length agnostic*). O programa pergunta ao hardware "quantos elementos cabem?"
  e faz o laço de acordo (§12.2).

### 11.3 O problema do AVX10.2 (resumo de [1])

O AVX-512 ganhou mais de 20 sub-extensões opcionais; o AVX10 tentou unificá-las, e o AVX10.2 (2024)
adicionou FP8 (E4M3 = "HF8", E5M2 = "BF8") e mais bfloat16. Resultado: nomes inconsistentes
(H = half, S = single, D = double ou *doubleword*, Q = *quadword*…), conversões para cada par de
formatos, instruções especiais por formato. A proposta de Hunhold:

1. **Agrupar** as instruções (bit a bit, máscara, inteiro, ponto flutuante, criptografia).
2. **Nomes sistemáticos de tamanho:** B8/B16/B32/B64 (bits crus), U8…U64 (sem sinal), S8…S64 (com sinal).
3. **Formatos numéricos:** apenas **T8, T16, T32, T64**.
4. **Generalizar:** toda operação existe para todos os tamanhos (fica barato porque o decodificador é comum).

Nosso projeto aplica o mesmo raciocínio à RVV, que já é bem mais regular que o x86.

---

## 12. RISC-V e a Extensão Vetorial (RVV)

### 12.1 RISC-V em uma página

RISC-V é uma ISA **aberta** e **modular**: uma base inteira (RV32I/RV64I) mais extensões
identificadas por letras — M (multiplicação), A (atômicas), **F** (FP32), **D** (FP64),
**Zfh** (FP16), **V** (vetorial, versão 1.0 ratificada em 2021) etc. Extensões novas podem
ser propostas por qualquer um; por convenção começam com **Z** (ex.: `Zvfh` = FP16 em vetores,
`Zvfbfmin`/`Zvfbfwma` = bfloat16 em vetores). Daí o nome da nossa proposta: **Zvtakum**.

### 12.2 Conceitos da RVV

| Conceito | O que é |
|---|---|
| **v0…v31** | 32 registradores vetoriais |
| **VLEN** | Tamanho de cada registrador em bits (definido pelo hardware: 128, 256, 512…) |
| **SEW** | *Selected Element Width*: tamanho de cada elemento (8, 16, 32, 64). **No Zvtakum, SEW=8/16/32 ⇒ T8/T16/T32** |
| **LMUL** | Agrupa 1, 2, 4 ou 8 registradores como se fossem um só (ou usa frações deles) |
| **VLMAX** | `VLEN × LMUL / SEW` — quantos elementos cabem |
| **vl** | Quantos elementos a instrução vai processar de fato (≤ VLMAX) |
| **vsetvli** | Instrução que configura SEW/LMUL e devolve `vl` |
| **Máscara (v0)** | Bit por elemento dizendo se aquela pista executa ou não |
| **Widening / narrowing** | Instruções cujo resultado tem o **dobro** (`vfw…`) ou a **metade** (`vfn…`) do SEW das entradas |

Exemplo de laço "vetor-agnóstico" (soma de vetores em FP32):

```asm
# a0 = n, a1 = &x, a2 = &y, a3 = &z      z[i] = x[i] + y[i]
loop:
    vsetvli t0, a0, e32, m1, ta, ma   # t0 = vl = min(n, VLMAX), SEW=32
    vle32.v  v1, (a1)                 # carrega vl elementos de x
    vle32.v  v2, (a2)                 # carrega vl elementos de y
    vfadd.vv v3, v1, v2               # soma elemento a elemento  ← vtadd.vv no Zvtakum
    vse32.v  v3, (a3)                 # grava z
    sub a0, a0, t0                    # n -= vl
    slli t1, t0, 2                    # bytes = vl * 4
    add a1, a1, t1
    add a2, a2, t1
    add a3, a3, t1
    bnez a0, loop
```

### 12.3 Nomes das instruções

`vfadd.vv` = **v**etorial, **f**loat, **add**, operandos **v**etor-**v**etor. Outros sufixos:
`.vf` (vetor e escalar float), `.vx` (vetor e escalar inteiro), `.vi` (imediato),
`.wv` (primeiro operando largo). Codificação (formato OP-V): `funct6 | vm | vs2 | vs1 | funct3 | vd | opcode` —
o `funct3` diz o tipo de operandos (OPFVV, OPFVF…) e o `funct6` diz a operação.
A especificação RVV 1.0 [6] traz as tabelas; na Fase 2 o grupo precisará escolher codificações
livres para as instruções Zvtakum.

### 12.4 Mapeamento proposto pelo enunciado

| Proposta (Zvtakum) | Operação | Equivalente RVV hoje | Observação |
|---|---|---|---|
| `vtadd.vv` | soma elemento a elemento | `vfadd.vv` | |
| `vtsub.vv` | subtração | `vfsub.vv` | pode reusar `vtadd` + negação inteira |
| `vtmul.vv` | multiplicação | `vfmul.vv` | |
| `vtdot.vv` | produto escalar com acúmulo largo | não existe `vfdot` na RVV 1.0; faz-se com `vfwmacc.vv` (multiplica-acumula alargando) + `vfredusum`/`vfredosum` (redução) | combina multiplicação, acúmulo alargado e redução |
| `vncvt.t.t` | conversão estreitando (T16 → T8, T32 → T16) | `vfncvt.f.f.w` | no takum = **arredondar a palavra e cortar bits** |

Note como a conversão fica trivial: alargar (T8 → T16) é **concatenar 8 zeros**, sem nenhuma
lógica; estreitar é arredondar como inteiro e saturar. Na RVV, cada par de formatos IEEE precisa
de lógica de conversão própria.

### 12.5 CSRs: onde o takum simplifica o estado da máquina

**CSR** = *Control and Status Register* (registradores de controle e status, lidos/escritos com
`csrr`/`csrw`). Os que interessam:

| CSR | Conteúdo | Com Zvtakum |
|---|---|---|
| `fcsr.frm` | Modo de arredondamento FP (3 bits; 5 modos) — as instruções vetoriais de FP sempre usam este modo | **Não é necessário**: takum tem um único modo |
| `fcsr.fflags` | Flags NV, DZ, OF, UF, NX | **Não é necessário**: sem ∞, sem NaN sinalizador, overflow/underflow saturam; NaR propaga pelo próprio valor |
| `vtype`, `vl`, `vlenb`, `vstart` | Configuração vetorial | Continuam iguais (independem do formato) |
| `vxrm`, `vxsat` | Arredondamento e saturação de ponto fixo vetorial | Não envolvidos |

Isso é o que o enunciado chama de "redução na complexidade do registro de controle e status":
**uma instrução takum não precisa ler `frm` nem escrever `fflags`** — ela é uma função pura das
entradas (critério 4, "sem estado"). Isso também elimina dependências entre instruções através
do `fcsr`, o que simplifica o pipeline. É uma hipótese que a Fase 3 deve medir/argumentar
(por exemplo: quantas instruções `csrr`/`csrw`/`fsrm` um kernel IEEE precisa e o kernel takum não).

> ⚠ **Não confunda:** "CSR" também é o nome de um formato de matriz esparsa
> (*Compressed Sparse Row*, §13.1). No relatório, deixe claro qual dos dois está em discussão.

---

## 13. Como o projeto será avaliado: SpMV, erro relativo e Float128

### 13.1 Matriz esparsa e SpMV

Uma matriz é **esparsa** quando quase todos os elementos são zero (ex.: uma matriz 10.000 × 10.000
com 50.000 não-zeros — 0,05% preenchida). Guardar os zeros seria desperdício; usa-se um formato
compacto. O mais comum é o **CSR (*Compressed Sparse Row*)**:

```
   A = [ 5 0 0 1 ]        valores  = [5, 1, 2, 3, 4]
       [ 0 2 0 0 ]        col_idx  = [0, 3, 1, 2, 0]
       [ 0 0 3 0 ]        row_ptr  = [0, 2, 3, 4, 5]   (onde cada linha começa em valores)
       [ 4 0 0 0 ]
```

**SpMV** (*Sparse Matrix-Vector multiplication*) é `y = A·x`. Para cada linha *i*:

```
   y[i] = Σ  valores[k] × x[col_idx[k]]      para k de row_ptr[i] até row_ptr[i+1]−1
```

Cada linha é um **produto escalar** — por isso a instrução `vtdot.vv` é central na Fase 3.
Os acessos `x[col_idx[k]]` são indiretos (instruções *gather* da RVV, `vluxei`/`vloxei`).
SpMV é o coração de solvers iterativos (gradiente conjugado, GMRES, Arnoldi) usados em
dinâmica de fluidos, estruturas, química etc. — daí ser um bom teste de "aritmética de uso geral".

Fonte das matrizes: **SuiteSparse Matrix Collection** [7] (antiga *University of Florida Sparse
Matrix Collection*), a mesma usada em [1]. A ferramenta de Hunhold, **MuFoLAB** [8], automatiza
esse tipo de benchmark (em Julia).

### 13.2 Medindo o erro

1. Calcule a **referência** `y_ref = A·x` em **Float128** (112 bits de fração — o erro dela é desprezível).
2. Converta `A` e `x` para o formato testado (T8, FP8, T16, FP16, …) e calcule `ỹ` **nesse formato**
   (no nosso simulador, com as instruções vetoriais).
3. Erro relativo na norma 2:

```
   erro = ‖ỹ − y_ref‖₂ / ‖y_ref‖₂          com  ‖v‖₂ = sqrt(Σ v_i²)
```

4. Repita para muitas matrizes e trace a **distribuição cumulativa**: eixo x = porcentagem das
   matrizes, eixo y = log10(erro), ordenando os erros do menor para o maior (como a Fig. 3 de [1]).
   Uma curva **mais baixa e que vai mais longe para a direita antes de "explodir"** é melhor.
   Marque como **∞** quando os valores da matriz saem da faixa do formato.

### 13.3 Outras métricas pedidas

- **Contagem de instruções:** quantas instruções o kernel executa com Zvtakum × com RVV+IEEE
  (incluindo conversões entre formatos e manipulação de `fcsr`).
- **Tamanho da ISA:** quantas instruções/variantes são necessárias para cobrir 8/16/32 bits
  em cada abordagem (o equivalente da contagem 756 → grupos unificados de [1]).

---

## 14. O que levar desta revisão para as próximas fases

**Decisões técnicas sugeridas (para validar com o grupo):**

1. **Variante:** takum **linear** (§8.6).
2. **Decodificador comum:** entrada = 12 bits mais significativos (T8 completado com zeros);
   saída = `S`, `D`, `r` (3 bits), `c` (9 bits com sinal, −255…254), posição de início da fração.
   A fração é extraída por um deslocamento de no máximo 7 posições (`r` ≤ 7).
3. **Negativos:** negar a palavra (complemento de 2) antes de decodificar e após codificar.
4. **Núcleo aritmético:** expoente de 9 bits com sinal e significando com bits guard/round/sticky,
   compartilhado por T8/T16/T32 (só a largura da fração muda).
5. **Codificador:** priority encoder para achar `r`, montagem dos campos, arredondamento sobre
   a palavra, saturação.
6. **Casos especiais:** apenas 0 e NaR.
7. **Oráculo de testes:** o modelo Python da §8.8 (e, para estreitamento/arredondamento,
   uma versão com `Fraction` que arredonda para o vizinho mais próximo).

**Checklist de conceitos** — se você consegue explicar cada item abaixo, a revisão cumpriu seu papel:

- [ ] Por que existe ponto flutuante e qual a troca entre bits de expoente e de fração
- [ ] Normal, subnormal, ±0, ±∞ e NaN no IEEE 754; bias; bit implícito
- [ ] Modos de arredondamento, RNE, guard/round/sticky; flags de exceção e o `fcsr`
- [ ] Por que existem bfloat16, E4M3 e E5M2 e por que isso fragmenta a ISA
- [ ] Precisão afunilada, fóvea e zona dourada
- [ ] Regime unário do posit × regime binário de 3 bits do takum
- [ ] Decodificar à mão um T8 (campos S, D, R, C, F → valor)
- [ ] Por que um único decodificador de 12 bits serve T8, T16 e T32
- [ ] Por que comparar/negar takums usa o hardware de inteiros
- [ ] Takum linear × logarítmico
- [ ] SEW, LMUL, `vl`, `vsetvli` na RVV; widening/narrowing
- [ ] SpMV em formato CSR, erro relativo na norma 2, distribuição cumulativa

---

## 15. Glossário

| Termo | Definição curta |
|---|---|
| **ALU / FPU** | Unidade lógico-aritmética / unidade de ponto flutuante |
| **bfloat16** | Float de 16 bits com 8 bits de expoente e 7 de fração (os 16 bits de cima do FP32) |
| **Bias (viés)** | Constante somada ao expoente do IEEE 754 para guardá-lo como inteiro sem sinal |
| **Característica (C, c)** | No takum, o campo/valor que dá o expoente |
| **CSR** | (1) *Control and Status Register* do RISC-V; (2) *Compressed Sparse Row*, formato de matriz esparsa |
| **Direção (D)** | Bit do takum que indica se a magnitude é ≥ 1 ou < 1 |
| **E4M3 / E5M2** | Os dois formatos FP8 da especificação OCP (4 ou 5 bits de expoente) |
| **Épsilon de máquina** | Erro relativo máximo de um arredondamento, ≈ 2^−(p+1) |
| **Faixa dinâmica** | Intervalo entre o menor e o maior valor positivo representável |
| **Float128** | IEEE 754 binary128 (quádrupla precisão), usado como referência |
| **FMA** | *Fused multiply-add*: a×b+c com um único arredondamento |
| **Fóvea** | Região de valores com o máximo de bits de fração num formato afunilado |
| **Ghost bits** | Bits-fantasma: zeros implícitos à direita de um posit/takum curto |
| **ISA** | *Instruction Set Architecture*: o "contrato" entre software e processador |
| **LMUL** | Fator de agrupamento de registradores vetoriais na RVV |
| **LNS** | *Logarithmic Number System*: o número é guardado pelo seu logaritmo |
| **Logaritmo gaussiano** | Φ±(q) = log(1 ± b^−q); necessário para somar em LNS |
| **NaN / NaR** | *Not a Number* (IEEE, muitos padrões) / *Not a Real* (posit/takum, um único padrão `100…0`) |
| **OFP8** | *OCP 8-bit Floating Point*: E4M3 e E5M2 |
| **Posit** | Formato afunilado de Gustafson; regime em código unário + 2 bits de expoente |
| **Quire** | Acumulador de ponto fixo largo do padrão posit para somas exatas de produtos |
| **Regime (R)** | Posit: prefixo unário que escala por 16^r. Takum: 3 bits que dão quantos bits de característica seguem |
| **RNE** | *Round to Nearest, ties to Even* |
| **RVV** | *RISC-V Vector Extension* |
| **Saturação** | Grampear resultados fora da faixa no maior/menor representável em vez de ∞/0 |
| **SEW** | *Selected Element Width*: tamanho dos elementos na RVV |
| **SIMD** | *Single Instruction, Multiple Data* |
| **SpMV** | Multiplicação matriz esparsa × vetor |
| **Subnormal** | Número IEEE com expoente mínimo e sem o "1," implícito, perto de zero |
| **T8/T16/T32/T64** | Takums de 8/16/32/64 bits |
| **Takum** | Formato afunilado de Hunhold (2024): sinal, direção, regime de 3 bits, característica de até 7 bits, fração |
| **Tapered precision** | Precisão afunilada: mais bits de fração perto de 1, menos nas extremidades |
| **ULP** | *Unit in the last place*: distância entre dois números representáveis vizinhos |
| **VLEN / vl** | Tamanho do registrador vetorial / número de elementos processados |
| **Zona Dourada** | Faixa em que um formato é pelo menos tão preciso quanto o IEEE 754 de mesmo tamanho |
| **Zvtakum** | Nome da extensão vetorial takum proposta neste projeto |

---

## 16. Referências

**Na pasta `papers/` do repositório:**

- **[1]** L. Hunhold, "Streamlining SIMD ISA Extensions with Takum Arithmetic: A Case Study on
  Intel AVX10.2," *MOCAST 2025*, pp. 1–6. arXiv:2503.14067. — `papers/2503.14067v2.pdf`
  *(Leia primeiro. 6 páginas; é o modelo do nosso projeto.)*
- **[2]** L. Hunhold, "Beating Posits at Their Own Game: Takum Arithmetic," in *Next Generation
  Arithmetic (CoNGA 2024)*, LNCS 14666, Springer, 2024, pp. 1–51. doi:10.1007/978-3-031-72709-2_1.
  arXiv:2404.18603. — `papers/2404.18603v2.pdf`
  *(Definição formal. Leia §1, §4.1, §4.2, §4.7 e §5.1–5.4; as provas podem ficar para depois.)*
- **[3]** *IEEE Standard for Floating-Point Arithmetic*, IEEE Std 754-2019. —
  `papers/IEEE Standard 754-2019.pdf` *(Consulta: §3.4–3.6 formatos, §4.3 arredondamento, §7 exceções.)*
- **[4]** J. L. Gustafson, *Every Bit Counts: Posit Computing*, CRC Press, 2024. —
  `papers/Every Bit Counts Posit Computing 1-9.pdf` e `…9-13.pdf`
  *(Didático. Cap. 1 formato posit; cap. 2 erro e precisão; cap. 4.7 história do IEEE 754;
  cap. 6 quire; cap. 8 sistemas logarítmicos; **§13.4 "The Hunhold Variation: Takum Format"**.)*
- **[5]** Posit Working Group, *Standard for Posit™ Arithmetic (2022)*. — `papers/posit_standard-2.pdf`

**Citadas pelos artigos acima e úteis para o projeto (fora da pasta):**

- **[6]** RISC-V International, *RISC-V "V" Vector Extension*, versão 1.0, 2021 —
  https://github.com/riscv/riscv-v-spec (hoje incorporada ao *RISC-V Unprivileged ISA Manual*).
- **[7]** T. A. Davis e Y. Hu, "The University of Florida Sparse Matrix Collection," *ACM TOMS*,
  vol. 38, no. 1, 2011 — https://sparse.tamu.edu
- **[8]** L. Hunhold e J. Quinlan, *MuFoLAB – Multi-Format Linear Algebra Benchmarks*, v1.2.0, 2025.
  doi:10.5281/zenodo.15001855.
- **[9]** L. Hunhold, "Design and Implementation of a Takum Arithmetic Hardware Codec in VHDL,"
  2024. arXiv:2408.10594. *(Muito útil para a Fase 1 em hardware.)*
- **[10]** L. Hunhold e J. Quinlan, "Evaluation of Bfloat16, Posit, and Takum Arithmetics in Sparse
  Linear Solvers," *IEEE ARITH 2025*. arXiv:2412.20268.
- **[11]** J. L. Gustafson e I. Yonemoto, "Beating Floating Point at Its Own Game: Posit Arithmetic,"
  *Supercomputing Frontiers and Innovations*, vol. 4, no. 2, pp. 71–86, 2017.
- **[12]** P. Micikevicius et al., *OCP 8-bit Floating Point Specification (OFP8)*, Open Compute
  Project, 2023.
- **[13]** Intel, *Intel® Advanced Vector Extensions 10.2 Architecture Specification*, 2024.
- **[14]** S. Wang e P. Kanwar, "BFloat16: The secret to high performance on Cloud TPUs," Google
  Cloud Blog, 2019.
- **[15]** L. Hunhold, J. Quinlan e S. Wesner, "Numerical Performance of the Implicitly Restarted
  Arnoldi Method in OFP8, Bfloat16, Posit, and Takum Arithmetics," 2025. arXiv:2504.21130.
- **[16]** F. de Dinechin et al., "Posits: the good, the bad and the ugly," *CoNGA 2019*
  (origem do termo "Golden Zone").

**Ordem de leitura sugerida:** este documento → [1] → [4] §13.4 → [2] §4 → [6] (capítulos de
configuração, `vsetvli` e instruções de ponto flutuante) → [9] (quando for implementar).
