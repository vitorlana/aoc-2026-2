# aoc-2026-2 

Projeto Integrador AOC 2026/02 — Formato aritmético Takum na Extensão Vetorial RISC-V (RVV).

## Entregáveis 

- **Artigo (IEEE, em inglês):** [docs/artigo/artigo.pdf](docs/artigo/artigo.pdf) · **versão em português:** [docs/artigo/artigo-pt.pdf](docs/artigo/artigo-pt.pdf)
- **Guia do projeto (explica tudo, passo a passo):** [docs/entrega2/guia.pdf](docs/entrega2/guia.pdf)
- **Slides da apresentação:** [docs/slides/slides.pdf](docs/slides/slides.pdf) 
- **Código:** RTL em `rtl/`, testes em `tb/`, simulador RVV e benchmarks em `sim/`, dados em `results/`
- **Matrizes reais:** cinco do Matrix Market (NIST), quatro da coleção Harwell-Boeing e uma grande (`memplus`, 17 758 linhas), em [`data/matrixmarket/`](data/matrixmarket/LEIAME.md)

## Documentação

- [Fase 1 — Revisão bibliográfica (HTML interativo)](docs/revisao-bibliografica.html) · [versão Markdown](docs/01-revisao-bibliografica.md)
- [Fase 1 — Guia do decodificador e codificador em Verilog](docs/02-fase1-decoder-encoder.md)
- [Fase 1 — Implementação: detalhes do código e como rodar](docs/03-fase1-implementacao.md) 
- [Entrega 1 — ALU (add/sub/mul) e instruções `vtadd.vv`, `vtsub.vv`, `vtmul.vv`](docs/04-entrega1-alu.md) · [relatório](docs/entrega1/entrega1.pdf)
- [Entrega 2 — `vtdot.vv`, `vncvt.t.t`, simulador RVV e avaliação experimental](docs/05-entrega2.md)
- Enunciado: `ProjectGuidelinesAOC.pdf`
- Artigos e livros de referência: `papers/`

## Ver o hardware

| | | 
|---|---|
| Esquemáticos (gerados do Verilog) | [cabeçalho](docs/img/takum_hdr_dec.png) · [decodificador](docs/img/takum_decoder.png) · [codificador](docs/img/takum_encoder.png) · [ALU](docs/img/takum_alu.png) · [produto alargado](docs/img/takum_wmul.png) · [`vncvt.t.t`](docs/img/takum_ncvt.png) · [`vtdot.vv`](docs/img/takum_dot.png) |
| Formas de onda | [decodificador](docs/img/ondas-parte1-decoder.png) · [codificador](docs/img/ondas-parte2-encoder.png) · [`vncvt.t.t`](docs/img/ondas-fase2-ncvt.png) · [produto alargado](docs/img/ondas-fase2-wmul.png) · [`vtdot.vv`](docs/img/ondas-fase2-vtdot.png) |

![vtdot.vv na unidade vetorial](docs/img/ondas-fase2-vtdot.png)

## Estado

| Item | Situação |
|---|---| 
| Decodificador e codificador takum (T8, T16, T32) | pronto, testado |
| ALU: soma, subtração, multiplicação | pronta; T8 exaustivo (65 536 pares × 3 operações), T16/T32 amostrados |
| Unidade vetorial: `vtadd.vv`, `vtsub.vv`, `vtmul.vv`, `vtdot.vv`, `vncvt.t.t` (SEW 8/16/32, `vl`, máscara) | pronta, testada |
| Simulador de instruções RV64I + RVV + Zvtakum | pronto; conferido contra os vetores do RTL |
| SpMV takum × IEEE 754 em 9 matrizes (4 geradas, 5 de repositório público), erro relativo contra Float128, contagem de instruções e CSRs | pronto; resultados em `results/` |
| Artigo e slides | prontos |

## Como rodar
 
Requer Icarus Verilog, Python 3 (só a biblioteca padrão) e make. Yosys, Verilator e LaTeX são opcionais.
Ubuntu/WSL: `sudo apt install iverilog python3 verilator yosys make`. macOS: `brew install icarus-verilog verilator yosys`.
 
```bash
make test      # RTL (decodificador, codificador, ALU, Fase 2, unidade vetorial) + simulador
make libtakum  # confere os vetores contra a libtakum, a referência do autor do formato (baixa a biblioteca)
make simdemo   # demonstração: produto escalar com vtdot.vv, instrução por instrução
make bench     # Fase 3: SpMV em takum e IEEE 754 -> results/
make synth     # Yosys: células/LUT6 por módulo e tamanho (synth2: blocos da Fase 2)
make schematic # esquemáticos de todos os módulos em docs/img/ (requer netlistsvg e rsvg-convert)
make waves2    # formas de onda da Fase 2 em docs/img/, sem GTKWave (waves: Fase 1 no GTKWave)
make lint      # Verilator -Wall
make paper     # artigo (inglês e português), guia e slides (LaTeX: IEEEtran, pgfplots, beamer)
```

O oráculo foi conferido contra a [libtakum](https://github.com/takum-arithmetic/libtakum): 826 987 vetores
idênticos e 16 produtos em T32 que diferem no último bit por limite de precisão da biblioteca.
 
A ALU e a unidade vetorial são verificadas contra `tb/takum_oracle.py`, que usa aritmética exata com
`Fraction` e não compartilha código com o RTL. O simulador usa o mesmo oráculo para o takum e executa os
vetores de teste do RTL como instruções codificadas, o que amarra os dois modelos.
