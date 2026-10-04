# Fase 1 — Guia: decodificador e codificador Takum (linear) em Verilog

**Projeto Integrador AOC 2026/02 — Zvtakum**

> **O que é este documento.** Um roteiro do que construir, em que ordem e como testar.
> Ele **não traz a implementação**: traz a especificação, as fórmulas já arrumadas para
> hardware, as perguntas que vocês precisam responder e os critérios de "pronto".
> O código Verilog é de vocês.
>
> **Decisões já tomadas pelo grupo:** Verilog, takum **linear**, tamanhos **T8, T16, T32**.
> **Tudo em Verilog**, inclusive o modelo de referência e os testes: nada de Python ou
> outra linguagem no fluxo.
>
> **Atualização:** a implementação já existe em `rtl/` e `tb/`; veja
> [`03-fase1-implementacao.md`](03-fase1-implementacao.md). Este guia continua valendo como explicação do raciocínio.
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
5. [Passo 1 — Modelo de referência em Verilog (só para teste)](#5-passo-1--modelo-de-referência-em-verilog-só-para-teste)
6. [Passo 2 — Decodificador](#6-passo-2--decodificador)
7. [Passo 3 — Codificador](#7-passo-3--codificador)
8. [Passo 4 — Testbenches](#8-passo-4--testbenches)
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
| 1 | Modelo de referência comportamental em Verilog (Passo 1) | pessoa A | 2–3 h |
| 2 | Decoder RTL (Passo 2) | pessoa B | 3–4 h |
| 3 | Encoder RTL (Passo 3) | pessoa C | 4–6 h |
| 4 | Testbenches (Passo 4) | pessoa A, depois todos | 2–3 h |
| 5 | Síntese com Yosys e tabela de recursos (Passo 5) | qualquer um | 1 h |

O modelo de referência vem **antes** e deve ser escrito por **outra pessoa** que não a do RTL:
se a mesma pessoa escreve os dois, o mesmo erro de entendimento aparece nos dois e o teste passa.

---

## 3. Ferramentas e estrutura do repositório

**Ferramentas sugeridas (todas gratuitas):**

| Ferramenta | Para quê |
|---|---|
| **Icarus Verilog** (`iverilog`, `vvp`) | Compilar e simular |
| **GTKWave** | Ver formas de onda (`$dumpfile` / `$dumpvars`) |
| **Verilator** (opcional) | Lint (`verilator --lint-only -Wall`) — pega muitos erros de largura |
| **Yosys** | Síntese genérica para contar células/LUTs (números para o artigo) |
| **make** | Um comando para rodar tudo (`make test`) |

Compilem com `iverilog -g2005` (ou `-g2012` se quiserem recursos de SystemVerilog no testbench).
O Icarus aceita o tipo `real` e as funções matemáticas do Verilog-2005 (`$pow`, `$ln`, `$floor`…),
que serão usados **só no testbench**.

**Estrutura sugerida:**

```
rtl/          takum_hdr_dec.v, takum_decoder.v, takum_encoder.v   (só RTL sintetizável)
tb/           takum_ref.vh       (modelo de referência: funções comportamentais, NÃO sintetizáveis)
              tb_decoder.v, tb_encoder.v, tb_roundtrip.v, tb_props.v
docs/         este guia + diagramas de blocos
Makefile      alvos: test, lint, synth, clean
```

Regras de ouro:

- **`rtl/` não inclui nada de `tb/`.** O modelo de referência vive só no testbench.
- **O testbench nunca "conserta" a saída do RTL** e nunca calcula o esperado reaproveitando o RTL.

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

## 5. Passo 1 — Modelo de referência em Verilog (só para teste)

Sem Python, o "gabarito" é um **modelo comportamental em Verilog**: funções que só existem no
testbench (`tb/takum_ref.vh`, incluído com `` `include ``), escritas para serem **claras e diferentes
do RTL**, sem se preocupar com hardware. Elas podem usar `real`, laços, `integer` e potências.

### 5.1 O que escrever

| Função (testbench) | Entrada → saída | Como escrever **diferente** do RTL |
|---|---|---|
| `ref_value(t, n)` → `real` | palavra takum → valor real | Use a **fórmula do artigo direto**, inclusive para negativos: `e = (−1)^S (c + S)` e `valor = ((1 − 3S) + f) · 2^e` (Def. 8 de [2]). O RTL usa negação + caso positivo; o modelo não. Assim um confere o outro. |
| `unpacked_value(sign, exp, frac, n)` → `real` | formato interno → valor real | `(−1)^sign · (1 + frac / 2^(N−5)) · 2^exp` |
| `ref_r_c(t, n, r, c)` (task) | palavra → `r`, `c` inteiros | Laços e `if`s com as fórmulas `c = 2^r − 1 + C` / `c = −2^(r+1) + 1 + C`, **não** as versões `{1,C} − 1` / `−{1,~C}` usadas no RTL |

Por que `real` serve de gabarito: um takum de até 32 bits tem no máximo 27 bits de fração e expoente
entre −255 e 254. Um `real` do Verilog é um *double* (53 bits de fração, expoente até ±1023), então
**todo valor T8/T16/T32 cabe nele exatamente**. Comparar com `==` é legítimo.

### 5.2 Testes do próprio modelo (façam antes do RTL)

Uma bateria pequena, num testbench `tb_ref.v`, que só exercita o modelo:

- Os exemplos da revisão: `0100_0000` → 1; `0100_0001` → 1,125; `0101_0000` → 8; `0111_1111` → 2²³⁹;
  `0000_0001` → 2⁻²³⁹; `1100_0000` → −1; `0011_1111` → 0,9375.
- Os exercícios da §12 deste guia.
- Para todos os T8 e T16: o valor de `−t` (complemento de 2) é `−ref_value(t)`, e
  `ref_value(t) < ref_value(t + 1)` percorrendo os inteiros com sinal (monotonicidade).

Se o modelo passar nisso, ele está fiel ao artigo, e pode julgar o RTL.

### 5.3 O codificador de referência (opcional)

Para o encoder, vocês **não precisam** de um codificador de referência: dá para verificar o RTL
por **propriedades** (§8.2), usando só `ref_value`. Se mesmo assim quiserem um, escrevam-no como
**busca**: dado um `real` x, percorra os padrões (exaustivo em T8/T16; busca binária em T32,
já que a ordem dos inteiros é a ordem dos valores) e escolha o vizinho mais próximo.

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

**Fórmulas já arrumadas para hardware** (equivalentes às do artigo; a §5 mostra como conferir):

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

- `unpacked_value(saídas)` igual a `ref_value(t)` para **todos os 256 T8** e **todos os 65.536 T16**, e as flags `is_zero`/`is_nar` corretas.
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
> não um bug. Por isso a checagem "vizinho mais próximo em valor" (§8.2) só vale para T16/T32 e para a
> região 2⁻¹⁵ ≤ |x| < 2¹⁶ de T8. (Verificamos: em T16 as duas regras coincidem em 20.000 valores
> aleatórios entre 2⁻⁶⁰ e 2⁶⁰.)

### 7.6 Critério de pronto do encoder

- **Ida e volta:** `encoder(decoder(x)) == x` para todos os T8 e T16 e para ≥ 1 milhão de T32 aleatórios.
- **Arredondamento:** as propriedades da §8.2 passando para entradas com `frac`, guard, round e sticky
  aleatórios, incluindo **empates exatos** (g = 1, s = 0) com último bit par e ímpar.
- **Saturação e casos especiais** da §10.
- Lint limpo.

---

## 8. Passo 4 — Testbenches

Todos os estímulos são gerados **dentro do testbench** (laços e `$random`), sem arquivos externos.

### 8.1 Estratégia

| Teste | Como | Cobertura |
|---|---|---|
| Modelo de referência | `tb_ref.v`: exemplos conhecidos + propriedades (§5.2) | antes de tudo |
| Decoder T8, T16 | Laço sobre todos os padrões; compara `unpacked_value(saídas)` com `ref_value(t)` | 100% dos padrões |
| Decoder T32 | `$random` com semente fixa + casos de borda da §10 | ≥ 10⁶ padrões |
| Ida e volta | `tb_roundtrip`: decoder → encoder, compara com a entrada | T8/T16 exaustivo, T32 aleatório |
| Encoder: arredondamento | Propriedades da §8.2 com `frac`/guard/round/sticky aleatórios | Milhares por tamanho |
| Saturação | Expoentes −300, −256, −255, 254, 255, 400 | Casos dirigidos |

O teste de **ida e volta** não precisa nem do modelo: é o RTL contra ele mesmo. Comecem por ele assim que
os dois módulos compilarem — pega a maior parte dos erros de campo.

### 8.2 Verificando o encoder sem um codificador de referência

Para uma entrada do encoder (`sign`, `exp`, `frac` com guard/round, `sticky`), calcule no testbench o valor
exato `x` (um `real`; com `sticky = 1`, some um "pouquinho" — por exemplo metade do peso do bit **round**, que fica abaixo de todos os bits de `frac` e não cria empate —
para representar que há bits descartados). O RTL devolve `t`. Então confira, usando só `ref_value`:

1. **Vizinhança:** `x` está entre `ref_value(t − 1)` e `ref_value(t + 1)` (vizinhos como inteiros; cuidado
   com as pontas: não existe vizinho além do maior/menor positivo).
2. **Mais próximo:** `|ref_value(t) − x|` ≤ distância de `x` para cada vizinho (na região onde o
   arredondamento é aritmético — veja a observação da §7.5).
3. **Empate:** se `x` está exatamente no meio, o último bit de `t` é 0.
4. **Saturação:** se `x` está acima do maior positivo, `t` é o maior positivo; abaixo do menor, o menor.
   Nunca `0` nem `100…0` para entrada diferente de zero/NaR.
5. **Sinal:** trocar `sign` na entrada dá o complemento de 2 de `t`.

Essas cinco checagens juntas equivalem a ter um codificador de referência, e são independentes do RTL.

### 8.3 Mecânica do testbench (o mínimo que funciona no Icarus)

- Instancie o DUT com o parâmetro (`takum_decoder #(.N(16)) dut (...)`). Para testar os três tamanhos no mesmo
  arquivo, instancie três vezes ou use um `generate`.
- Num laço `for`, aplique a entrada, espere `#1` (é combinacional) e compare.
- Para T32 aleatório: `seed = 32'd2026; x = $random(seed);` — semente fixa = teste reproduzível.
- Em erro, imprima com `$display` a entrada, o esperado e o obtido **em hexadecimal e em decimal**
  (`%h`, `%d`, e `%e` para `real`), conte os erros e pare depois de uns 20.
- No final, imprima `PASS`/`FAIL` e o número de casos — o `Makefile` pode procurar essa palavra.
- Gerem `.vcd` (`$dumpfile`/`$dumpvars`) só ao depurar um caso específico: o exaustivo de T16 gera arquivos enormes.

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

Para cada tamanho N, os testes precisam cobrir pelo menos:

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
- **Testbench que reaproveita a lógica do RTL** para calcular o esperado. O esperado vem do modelo de referência, escrito de outro jeito e por outra pessoa.
- **Usar `real` dentro de `rtl/`.** `real`, `$pow`, laços com `integer` de tamanho variável etc. são só para o testbench; não sintetizam.
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
- [ ] Modelo de referência em Verilog (`tb/takum_ref.vh`) com `ref_value` e `unpacked_value`, passando no `tb_ref.v`
- [ ] Testbenches com semente fixa e mensagens de erro legíveis
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
