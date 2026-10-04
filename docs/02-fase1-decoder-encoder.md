# Fase 1 — Guia: decodificador e codificador Takum (linear) em Verilog

**Projeto Integrador AOC 2026/02 — Zvtakum**

> **O que é este documento.** Um roteiro do que construir, em que ordem e como testar.
> Ele **não traz a implementação**: traz a especificação, as fórmulas já arrumadas para
> hardware, as perguntas que vocês precisam responder e os critérios de "pronto".
> O código Verilog é de vocês.
>
> **Decisões já tomadas pelo grupo:** Verilog, takum **linear**, tamanhos **T8, T16, T32**.
>
> **Pré-requisito:** ter lido os capítulos "Takum" e "Aritmética" da revisão
> ([`revisao-bibliografica.html`](revisao-bibliografica.html) ou
> [`01-revisao-bibliografica.md`](01-revisao-bibliografica.md), §8 e §9).

---

## Sumário

1. [Onde o decoder e o encoder entram](#1-onde-o-decoder-e-o-encoder-entram)
2. [Prazo e ordem de trabalho](#2-prazo-e-ordem-de-trabalho)
3. [Ferramentas e estrutura do repositório](#3-ferramentas-e-estrutura-do-repositório)
4. [Passo 0 — Definir o formato interno (antes de qualquer Verilog)](#4-passo-0--definir-o-formato-interno-antes-de-qualquer-verilog)
5. [Passo 1 — Modelo de referência em Python](#5-passo-1--modelo-de-referência-em-python)
6. [Passo 2 — Decodificador](#6-passo-2--decodificador)
7. [Passo 3 — Codificador](#7-passo-3--codificador)
8. [Passo 4 — Testbenches e vetores de teste](#8-passo-4--testbenches-e-vetores-de-teste)
9. [Passo 5 — Síntese e números para o relatório](#9-passo-5--síntese-e-números-para-o-relatório)
10. [Casos de borda (lista de conferência)](#10-casos-de-borda-lista-de-conferência)
11. [Erros comuns](#11-erros-comuns)
12. [Exercícios de aquecimento (com respostas)](#12-exercícios-de-aquecimento-com-respostas)
13. [Checklist de "pronto"](#13-checklist-de-pronto)

---

## 1. Onde o decoder e o encoder entram

Toda operação takum da Fase 1 (e depois as instruções `vtadd`, `vtmul`… da Fase 2) segue o mesmo caminho:

```
 takum A ─► [DECODER] ─┐                                    
                       ├─► [NÚCLEO: soma / multiplicação] ─► [ENCODER] ─► takum resultado
 takum B ─► [DECODER] ─┘     (trabalha no formato interno)    (arredonda e satura)
```

- O **decoder** transforma uma palavra de N bits em um **formato interno** fácil de operar
  (sinal, expoente, significando, flags de zero/NaR).
- O **encoder** faz o caminho inverso, incluindo **arredondamento** e **saturação**.
- O núcleo aritmético (próxima etapa) só conversa com o formato interno. Por isso o
  formato interno é a decisão mais importante desta etapa (Passo 0).

Nesta etapa vocês entregam **apenas decoder e encoder**, testados exaustivamente.
Um bom teste de integração é o "ida e volta": `encoder(decoder(x)) == x` para todo x.

---

## 2. Prazo e ordem de trabalho

O cronograma do enunciado marca a **ALU e as instruções básicas (T8/T16/T32) para 11/10/2026**.
Decoder e encoder são a base disso, então a sugestão é fechá-los nos primeiros dias:

| Ordem | Tarefa | Quem pode fazer em paralelo | Estimativa |
|---|---|---|---|
| 0 | Fechar o formato interno (Passo 0) e escrever no repositório | grupo todo, juntos | 1 h |
| 1 | Modelo Python + gerador de vetores (Passo 1) | pessoa A | 2–3 h |
| 2 | Decoder em Verilog (Passo 2) | pessoa B | 3–4 h |
| 3 | Encoder em Verilog (Passo 3) | pessoa C | 4–6 h |
| 4 | Testbenches (Passo 4) | pessoa A, depois todos | 2–3 h |
| 5 | Síntese com Yosys e tabela de recursos (Passo 5) | qualquer um | 1 h |

O modelo Python vem **antes** porque é ele que diz se o Verilog está certo.

---

## 3. Ferramentas e estrutura do repositório

**Ferramentas sugeridas (todas gratuitas):**

| Ferramenta | Para quê |
|---|---|
| **Icarus Verilog** (`iverilog`, `vvp`) | Compilar e simular |
| **GTKWave** | Ver formas de onda (`$dumpfile` / `$dumpvars`) |
| **Verilator** (opcional) | Lint (`verilator --lint-only -Wall`) — pega muitos erros de largura |
| **Yosys** | Síntese genérica para contar células/LUTs (números para o artigo) |
| **Python 3** | Modelo de referência e geração de vetores |
| **make** | Um comando para rodar tudo (`make test`) |

**Estrutura sugerida:**

```
rtl/          takum_hdr_dec.v, takum_decoder.v, takum_encoder.v   (só RTL sintetizável)
tb/           tb_decoder.v, tb_encoder.v, tb_roundtrip.v
model/        takum.py           (modelo de referência)
              gen_vectors.py     (gera os arquivos de vetores)
vectors/      dec_t8.hex, dec_t16.hex, dec_t32.hex, enc_t16.hex, ...   (gerados; podem ir no .gitignore)
docs/         este guia + diagramas de blocos
Makefile      alvos: vectors, test, lint, synth, clean
```

Regra de ouro: **`rtl/` não importa nada de `tb/`**, e o testbench nunca "conserta" a saída do RTL.

---

## 4. Passo 0 — Definir o formato interno (antes de qualquer Verilog)

Escrevam esta especificação num arquivo (por exemplo `docs/formato-interno.md`) e não mudem
sem combinar. Abaixo está uma **proposta**; vocês podem alterar, mas justifiquem no relatório.

### 4.1 Proposta de formato interno ("desempacotado")

| Sinal | Largura | Significado |
|---|---|---|
| `is_zero` | 1 | A entrada era `000…0` |
| `is_nar` | 1 | A entrada era `100…0` |
| `sign` | 1 | 0 positivo, 1 negativo |
| `exp` | **9 bits com sinal** | Expoente `e` do valor `±(1 + f) × 2^e`, de −255 a +254 |
| `frac` | `N − 5` bits | Fração **alinhada à esquerda** (o bit mais significativo de `frac` vale 1/2). Bits que o número não tem ficam em 0 |

Com isso, o valor representado é `(−1)^sign × (1 + frac / 2^(N−5)) × 2^exp`.

**Perguntas que o grupo precisa responder (e registrar):**

1. Por que `exp` precisa de 9 bits com sinal? (Dica: qual o maior e o menor `e`?)
2. Por que `N − 5` bits de fração bastam para qualquer takum de N bits? (Dica: qual o menor `r` possível?)
3. Para T8, `N − 5 = 3`. Para T32, `27`. Faz sentido o mesmo módulo ter `frac` de largura parametrizada?
4. **Sinal-magnitude ou não?** A proposta usa sinal-magnitude (sinal separado, `1 + f` positivo).
   O próprio takum guarda negativos como `(−2 + f) × 2^e`. Para o núcleo aritmético, sinal-magnitude
   é muito mais simples. Confirmem a escolha.

### 4.2 Entrada do encoder (o que o núcleo vai entregar)

O núcleo aritmético vai produzir resultados com **mais bits** do que cabem e com **expoente fora da faixa**
(ex.: multiplicar dois números de expoente 200 dá 400). Então a entrada do encoder deve ser mais larga:

| Sinal | Largura sugerida | Por quê |
|---|---|---|
| `sign` | 1 | |
| `exp` | **11 bits com sinal** | Multiplicação soma expoentes: −510…+508, mais folga para normalização |
| `frac` | `N − 5 + 2` bits (ou mais) | Fração + bit **guard** + bit **round** |
| `sticky` | 1 | OU de todos os bits que o núcleo já descartou |
| `is_zero`, `is_nar` | 1 cada | Casos especiais passam direto |

> Combinem com quem vai fazer a soma/multiplicação **agora**, para não ter que refazer o encoder.

---

## 5. Passo 1 — Modelo de referência em Python

Partam do `takum_linear_decode` que está na revisão (§8.8 do Markdown / capítulo Takum do HTML).
Ele já foi conferido contra o livro e o artigo. O que falta vocês escreverem:

1. **`decode_unpacked(bits, n)`** → devolve exatamente o formato interno do Passo 0
   (`is_zero, is_nar, sign, exp, frac`). É o "gabarito" do decoder Verilog.
2. **`encode(sign, exp, frac, guard, round, sticky, n)`** → devolve os N bits, seguindo
   **as mesmas regras** que o hardware vai seguir (seção 7). É o gabarito do encoder.
3. **`nearest_takum(x, n)`** por força bruta (procura o vizinho mais próximo entre todos os padrões).
   Serve para conferir o `encode` do próprio modelo em T16/T32.
4. **`gen_vectors.py`**: escreve arquivos `.hex`, uma linha por caso, com entrada e saída esperada
   concatenadas. Ex.: para o decoder de T16, cada linha pode ter `entrada(16) | zero | nar | sign | exp(9) | frac(11)`.

**Testes do próprio modelo (façam antes do Verilog):**

- `decode` de todos os T8 e T16 bate com `takum_linear_decode`.
- `encode(decode_unpacked(x)) == x` para todos os T8 e T16.
- Para valores aleatórios em T16, `encode` = `nearest_takum` (veja a observação sobre T8 na §7.5).

---

## 6. Passo 2 — Decodificador

### 6.1 Interface sugerida

```
module takum_decoder #(parameter N = 16) (
    input  [N-1:0]   t,          // palavra takum
    output           is_zero,
    output           is_nar,
    output           sign,
    output [8:0]     exp,        // com sinal
    output [N-6:0]   frac        // N-5 bits, alinhada à esquerda
);
```

Combinacional (sem clock) nesta etapa. Pipeline, se quiserem, fica para depois.

### 6.2 Diagrama de blocos

```
 t[N-1:0]
   │
   ├──► [detecta 0 e NaR] ──────────────────────────────► is_zero, is_nar
   │
   ├──► sign = t[N-1]
   │
   └──► [negação condicional: se sign, complemento de 2] ──► u[N-1:0]   (u é sempre "positivo")
              │
              ├──► [cabeçalho: completa até 12 bits com zeros à direita]
              │          │
              │          ▼
              │    [takum_hdr_dec]  D, R ──► r ;  C ──► c = exp
              │
              └──► [deslocador: u << (5 + r)] ──► frac (N−5 bits do topo)
```

### 6.3 Por que negar primeiro

Pela propriedade de negação do takum, `valor(−t) = −valor(t)`, onde `−t` é o complemento de 2.
Então: **se o sinal é 1, nego a palavra, decodifico como positivo e devolvo `sign = 1`.**
Com isso vocês só precisam implementar o caso S = 0, em que `valor = (1 + f) × 2^c`, ou seja, **`exp = c`**.

Pergunta para o grupo: o que acontece com NaR (`100…0`) ao passar pelo negador? E com 0?
Isso afeta a lógica? (Os flags `is_zero`/`is_nar` resolvem, mas entendam por quê.)

### 6.4 O cabeçalho de 12 bits (o coração do projeto)

Depois da negação, olhe só os **12 bits mais significativos** de `u` (para T8, complete com 4 zeros
à direita — os *ghost bits*). Chame-os `h[11:0]`:

| Bits de `h` | Campo |
|---|---|
| `h[11]` | S (é 0 depois da negação) |
| `h[10]` | D |
| `h[9:7]` | R |
| `h[6:0]` | janela de 7 bits onde mora C (só os `r` primeiros são de C) |

**Fórmulas já arrumadas para hardware** (todas conferidas no modelo Python):

| Grandeza | Fórmula | Dica de hardware |
|---|---|---|
| `r` | `D ? R : 7 − R` | `7 − R` em 3 bits é **inverter os 3 bits** de R |
| `C` | os `r` bits mais significativos da janela `h[6:0]` | deslocar a janela para a direita de `7 − r` |
| `c` (se D = 1) | `c = {1, C} − 1` | "1" seguido dos `r` bits de C, menos 1. Vai de 0 a 254 |
| `c` (se D = 0) | `c = −{1, ~C}` | "1" seguido de C **invertido**, com sinal trocado. Vai de −255 a −1 |

> Confiram à mão: D = 1, r = 2, C = `01` → `{1,C}` = `101` = 5 → c = 4.
> D = 0, r = 2, C = `01` → `~C` = `10` → `{1,~C}` = `110` = 6 → c = −6.
> Batem com as fórmulas do artigo (`c = 2^r − 1 + C` e `c = −2^(r+1) + 1 + C`)?

**Sugestão forte:** façam o cabeçalho como um **módulo separado** (`takum_hdr_dec`, entrada de 12 bits)
e instanciem o **mesmo** módulo em T8, T16 e T32. Isso demonstra no artigo a afirmação central de
Hunhold: *um único decodificador de 12 bits serve todas as precisões* [1, §I], [2, §5.2].

Duas formas de implementar `c` — testem as duas se tiverem tempo e comparem na síntese:

1. **Lógica direta:** deslocador da janela + somador/subtrator de 9 bits.
2. **Tabela por regime:** são só 8 valores de `r`; para cada um, uma máscara e um deslocamento
   fixos [2, §5.2]. Em Verilog isso vira um `case (r)`.

### 6.5 A fração

Os bits de fração começam na posição `5 + r` (contando a partir do MSB). Então:

- desloque `u` para a esquerda de `5 + r` posições;
- os `N − 5` bits do topo do resultado são `frac`, já alinhada à esquerda e com zeros onde não há bits.

Observações:

- Como `r ≤ 7`, o deslocamento é de 5 a 12 posições: um **barrel shifter de 3 bits de controle**
  (mais um deslocamento fixo de 5). Comparem com o posit, onde o deslocamento pode ser quase N.
- Em T8 com `r > 3`, alguns bits de C caem fora da palavra: são ghost bits (zeros) e a fração é vazia.
  O cabeçalho completado com zeros já cuida disso; confirmem que o deslocador não lê lixo.

### 6.6 Critério de pronto do decoder

- Saída idêntica ao modelo para **todos os 256 T8** e **todos os 65.536 T16**.
- T32: pelo menos 1 milhão de padrões aleatórios + todos os casos da §10.
- `verilator --lint-only -Wall` sem avisos de largura.

---

## 7. Passo 3 — Codificador

### 7.1 Interface sugerida

```
module takum_encoder #(parameter N = 16) (
    input            is_zero,
    input            is_nar,
    input            sign,
    input  [10:0]    exp,        // com sinal, pode estar fora de −255..254
    input  [N-4:0]   frac,       // N-5 bits de fração + guard + round
    input            sticky,
    output [N-1:0]   t
);
```

### 7.2 Diagrama de blocos

```
 exp, frac, sticky, sign
   │
   ├──► [fora da faixa?] ── exp > 254  ─► maior positivo  (0111…1)
   │                    └─ exp < −255 ─► menor positivo  (000…01)
   │
   ├──► D = (exp ≥ 0)
   ├──► r = posição do 1 mais significativo de (exp + 1) se D=1, de (−exp) se D=0   ← priority encoder
   ├──► R = D ? r : ~r          C = r bits de baixo de (exp + 1)  ou  de ~(−exp)
   │
   ├──► [monta palavra longa]  0 | D | R | C (r bits) | frac | ...   ← deslocamento variável por r
   │
   ├──► [corta para N bits + arredonda (RNE na palavra)]
   │
   ├──► [satura: 0 → menor positivo ; estouro → maior positivo]
   │
   └──► [negação condicional: se sign, complemento de 2] ──► mux com 0 / NaR ──► t
```

### 7.3 Achando D, r, R e C (o inverso das fórmulas do decoder)

Partindo das fórmulas do decoder (`c = {1,C} − 1` e `c = −{1,~C}`), com `c = exp`:

| | D = 1 (`exp ≥ 0`) | D = 0 (`exp < 0`) |
|---|---|---|
| Valor auxiliar | `a = exp + 1` (1 a 255) | `a = −exp` (1 a 255) |
| `r` | posição do 1 mais significativo de `a` | posição do 1 mais significativo de `a` |
| `C` | os `r` bits abaixo desse 1 em `a` | os `r` bits abaixo desse 1 em `a`, **invertidos** |
| `R` | `r` | `~r` (3 bits) |

O "posição do 1 mais significativo" de um número de 8 bits é um **priority encoder 8→3**. É a única
peça "esperta" do encoder.

Exercício: refaçam o caminho para `exp = 4` e `exp = −6` e confiram que voltam a C = `01` nos dois casos.

### 7.4 Montagem e arredondamento

1. Monte, numa palavra **mais larga que N**, a sequência
   `0 | D | R(3) | C(r bits) | frac (com guard e round)`. Como C tem tamanho variável,
   o `frac` fica num lugar que depende de `r` — de novo um deslocamento controlado por 3 bits.
2. Separe:
   - os **N bits de cima** → candidato `w`;
   - o **primeiro bit descartado** → `g` (guard);
   - o **OU de todos os outros descartados**, mais o `sticky` de entrada → `s`.
3. **Arredondamento para o mais próximo, empate para o par, sobre a palavra inteira:**
   some 1 em `w` quando `g = 1` e (`s = 1` ou o último bit de `w` for 1).

**Por que somar 1 na palavra funciona**, mesmo quando o "vai-um" atravessa a fração e entra em C, R ou D:
o takum é **monótono** (Prop. 4 de [2]) — o padrão seguinte, como inteiro, é sempre o próximo
número takum. O carry faz a mudança de expoente "sozinho". Essa é a mesma ideia do Algoritmo 1 de [2]
e do padrão posit. Escrevam isso no relatório: é uma vantagem real de hardware.

### 7.5 Saturação (takum nunca vira 0 nem ∞ por estouro)

Depois do arredondamento:

- Se a palavra deu **0** mas a entrada não era zero → use o **menor positivo** `000…01`.
- Se o "vai-um" chegou ao bit de sinal (a palavra virou `100…0`, que é NaR) → use o **maior positivo** `011…1`.
- Por último, se `sign = 1`, faça o **complemento de 2**.
- `is_nar` → `100…0`; `is_zero` → `000…0` (têm prioridade sobre tudo).

> **Observação importante para os testes (T8):** quando o arredondamento descarta bits de **característica**
> (só acontece em T8, para |x| ≥ 2¹⁶ ou |x| < 2⁻¹⁵), arredondar a palavra **não** dá o vizinho mais próximo
> em valor — o ponto médio deixa de ser aritmético. Isso é o comportamento definido pelo Algoritmo 1 de [2],
> não um bug. O modelo Python do encoder deve seguir **a regra da palavra**, e a comparação com
> `nearest_takum` (força bruta) só vale para T16/T32 e para a região "normal" de T8.
> (Verificamos: em T16 as duas regras coincidem em 20.000 valores aleatórios entre 2⁻⁶⁰ e 2⁶⁰.)

### 7.6 Critério de pronto do encoder

- **Ida e volta:** `encoder(decoder(x)) == x` para todos os T8 e T16 e para ≥ 1 milhão de T32 aleatórios.
- **Arredondamento:** vetores gerados pelo modelo com `frac` mais larga que o formato (bits guard/round/sticky
  ligados), incluindo **empates exatos** (g = 1, s = 0) com último bit par e ímpar.
- **Saturação e casos especiais** da §10.
- Lint limpo.

---

## 8. Passo 4 — Testbenches e vetores de teste

### 8.1 Estratégia

| Teste | Como | Cobertura |
|---|---|---|
| Decoder T8, T16 | Exaustivo, vetores do modelo | 100% dos padrões |
| Decoder T32 | Aleatório + casos de borda | ≥ 10⁶ padrões |
| Ida e volta | `tb_roundtrip`: decoder → encoder, compara com a entrada | T8/T16 exaustivo, T32 aleatório |
| Encoder com arredondamento | Vetores do modelo: valores entre dois takums vizinhos, empates, sticky | Milhares por tamanho |
| Saturação | Expoentes −300, −256, −255, 254, 255, 400 | Casos dirigidos |

O teste de **ida e volta** não precisa do Python: é o RTL contra ele mesmo. Comecem por ele assim que
os dois módulos compilarem — pega a maior parte dos erros de campo.

### 8.2 Mecânica do testbench (o mínimo que funciona no Icarus)

- Leia os vetores com `$readmemh("vectors/dec_t16.hex", mem);` para um array.
- Num laço, aplique a entrada, espere `#1`, compare **cada campo** com o esperado.
- Em erro, imprima com `$display` a entrada, o esperado e o obtido **em hexadecimal e em decimal**, e
  conte os erros. Pare após, digamos, 20 erros para não inundar o terminal.
- No final, imprima `PASS`/`FAIL` e o número de casos — o `Makefile` pode procurar essa palavra.
- Gerem um `.vcd` só quando estiverem depurando (o exaustivo de T16 gera arquivos grandes).

### 8.3 Organização dos vetores

- Um arquivo por (módulo, tamanho). Formato simples: campos concatenados em hexadecimal, um caso por linha.
- Documentem o layout de cada linha no topo do `gen_vectors.py`.
- Gerem os vetores com uma **semente fixa** (`random.seed(…)`) para que os testes sejam reproduzíveis.

---

## 9. Passo 5 — Síntese e números para o relatório

O artigo precisa de resultados. Com o Yosys, sintetizem cada módulo para T8, T16 e T32 e registrem:

| Módulo | N | Células (Yosys `stat`) | Observação |
|---|---|---|---|
| `takum_hdr_dec` | (12 fixo) | | igual para todos os N |
| `takum_decoder` | 8 / 16 / 32 | | |
| `takum_encoder` | 8 / 16 / 32 | | |

Comandos úteis: `read_verilog`, `chparam -set N 16 <top>`, `synth -top <top>`, `stat`.
Se a disciplina tiver uma FPGA de referência, usem também o fluxo dela (LUTs e atraso).

**O que mostrar no artigo (Methodology):**

- Diagrama de blocos do decoder e do encoder (os da §6.2 e §7.2, redesenhados).
- A tabela acima, destacando que `takum_hdr_dec` **não cresce com N** e que o crescimento do decoder
  vem só do negador e do deslocador da fração.
- Comparação qualitativa com um decoder posit (regime unário → contador de zeros/uns do tamanho da palavra).

---

## 10. Casos de borda (lista de conferência)

Para cada tamanho N, os vetores precisam conter pelo menos:

| Caso | Padrão (T8 como exemplo) | Esperado |
|---|---|---|
| Zero | `0000_0000` | `is_zero` |
| NaR | `1000_0000` | `is_nar` |
| Um | `0100_0000` | `sign=0, exp=0, frac=0` |
| Menos um | `1100_0000` | `sign=1, exp=0, frac=0` |
| Maior positivo | `0111_1111` | T8: `exp = 239`; T16/T32: `exp = 254` e fração toda 1 |
| Menor positivo | `0000_0001` | T8: `exp = −239`; T16/T32: `exp = −255` |
| Maior negativo (mais perto de 0) | `1111_1111` | simétrico do menor positivo |
| Menor negativo | `1000_0001` | simétrico do maior positivo |
| Cada um dos 8 regimes, com D = 0 e D = 1 | variar R | `r` de 0 a 7 |
| Fronteiras de regime | ex.: `exp` = 0, 1, 2, 3, 6, 7, 14, 15, 30, 31… e negativos −1, −2, −3, −4, −7, −8… | troca de `r` |
| Encoder: `exp` = 254, 255, −255, −256 | | 255 e −256 saturam |
| Encoder: arredondamento que propaga carry até C/R/D | fração toda 1 + guard | sobe o expoente |
| Encoder: carry até o sinal | maior positivo + arredondar para cima | satura no maior, **não** vira NaR |
| Encoder: resultado arredonda para 0 | menor positivo × 0,4 | satura no menor, **não** vira 0 |
| Encoder: empates | g = 1, s = 0, LSB 0 e LSB 1 | mantém / sobe |

---

## 11. Erros comuns

- **Larguras e sinal em Verilog.** Misturar `signed` e não-`signed` numa expressão faz a expressão
  inteira virar sem sinal. Declarem explicitamente (`wire signed [8:0] exp`) e usem `$signed()` com cuidado.
  Rodem o Verilator em modo lint.
- **`7 − R` com aritmética** em vez de inverter bits: funciona, mas gasta um subtrator à toa.
- **Esquecer os ghost bits em T8**: ler bits além do LSB sem completar com zeros.
- **Deslocamento com quantidade de largura errada**: `u << (5 + r)` com `r` de 3 bits estoura se a soma
  for calculada em 3 bits. Pensem na largura de `5 + r`.
- **Arredondar antes de saturar a faixa de expoente**, ou saturar antes de tratar zero/NaR. A ordem é:
  especiais → faixa de expoente → montar → arredondar → saturar resultado → negar.
- **Testbench que reaproveita a lógica do RTL** para calcular o esperado. O esperado vem do Python.
- **Negar NaR ou zero** e achar que o resultado está errado: `−0 = 0` e `−NaR = NaR` em complemento de 2.

---

## 12. Exercícios de aquecimento (com respostas)

Façam à mão antes de codificar (ou usem o decodificador interativo da página HTML para conferir).

**Decodifique (T8):**

| # | Bits | Pergunta |
|---|---|---|
| a | `0101_0000` | r, c, valor? |
| b | `0011_0000` | r, c, valor? |
| c | `1011_0000` | valor? (use a negação) |
| d | `0110_1000` | r, c, valor? |

**Codifique (T16, sem arredondamento):**

| # | Valor | Pergunta |
|---|---|---|
| e | 3 | bits? |
| f | 0,25 | bits? |

<details>
<summary>Respostas</summary>

- a) D=1, R=010 → r=2, C=`00` → c = `{1,00}` − 1 = 3 → **8**.
- b) D=0, R=110 → r = 7 − 6 = 1, C=`0` → c = −`{1,1}` = −3 → **0,125**.
- c) Complemento de 2 de `1011_0000` = `0101_0000` = 8 → **−8**.
- d) D=1, R=101 → r=5, C = `000` + 2 ghost bits = `00000` → c = 2⁵ − 1 = 31 → **2³¹**.
- e) 3 = 1,5 × 2¹ → exp=1, D=1, a=2 → r=1, C=`0`, R=`001`, fração `1` → `0 1 001 0 1000000000` = **`0x4A00`**.
- f) 0,25 = 1,0 × 2⁻² → exp=−2, D=0, a=2 → r=1, C = ~`0` = `1`, R = ~`001` = `110` → `0 0 110 1 0000000000` = **`0x3400`**.

</details>

---

## 13. Checklist de "pronto"

- [ ] Formato interno escrito e combinado com quem fará a soma/multiplicação
- [ ] Modelo Python: `decode_unpacked`, `encode`, `nearest_takum` e autotestes passando
- [ ] `gen_vectors.py` com semente fixa e layout documentado
- [ ] `takum_hdr_dec` (12 bits) como módulo próprio, reutilizado em T8/T16/T32
- [ ] `takum_decoder` passando exaustivo T8/T16 e aleatório T32
- [ ] `takum_encoder` passando ida e volta, arredondamento, empates e saturação
- [ ] `make test` roda tudo e termina com PASS
- [ ] Lint (Verilator) sem avisos
- [ ] Tabela de síntese (Yosys) para T8/T16/T32
- [ ] Diagramas de blocos para o artigo
- [ ] Decisões e justificativas registradas (formato interno, regra de arredondamento, tabela × lógica direta)

---

### Referências usadas neste guia

- [1] L. Hunhold, *Streamlining SIMD ISA Extensions with Takum Arithmetic: A Case Study on Intel AVX10.2*, MOCAST 2025 — `papers/2503.14067v2.pdf`
- [2] L. Hunhold, *Beating Posits at Their Own Game: Takum Arithmetic*, CoNGA 2024 — `papers/2404.18603v2.pdf` (Def. 8: takum linear; Alg. 1: arredondamento; Alg. 4: codificação; §5.2: hardware)
- [9] L. Hunhold, *Design and Implementation of a Takum Arithmetic Hardware Codec in VHDL*, 2024, arXiv:2408.10594 — **leiam depois de tentar**: é uma implementação de referência em VHDL e serve para comparar decisões e resultados de síntese.
