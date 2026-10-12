# aoc-2026-2

Projeto Integrador AOC 2026/02 — Formato aritmético Takum na Extensão Vetorial RISC-V (RVV).

## Documentação

- [Fase 1 — Revisão bibliográfica (HTML interativo)](docs/revisao-bibliografica.html) · [versão Markdown](docs/01-revisao-bibliografica.md)
- [Fase 1 — Guia do decodificador e codificador em Verilog](docs/02-fase1-decoder-encoder.md)
- [Fase 1 — Implementação: detalhes do código e como rodar](docs/03-fase1-implementacao.md)
- [Entrega 1 — ALU (add/sub/mul) e instruções `vtadd.vv`, `vtsub.vv`, `vtmul.vv`](docs/04-entrega1-alu.md)
- Enunciado: `ProjectGuidelinesAOC.pdf`
- Artigos e livros de referência: `papers/`

## Estado

| Item | Situação |
|---|---|
| Decodificador e codificador takum (T8, T16, T32) | pronto, testado |
| ALU: soma, subtração, multiplicação | pronta; T8 exaustivo (65 536 pares × 3 operações), T16/T32 amostrados |
| Unidade vetorial `vtadd.vv`, `vtsub.vv`, `vtmul.vv` (SEW 8/16/32, `vl`) | pronta, testada |
| `vtdot.vv`, `vncvt.t.t`, integração no modelo RVV | pendente (Fase 2) |
| Benchmarks de álgebra linear esparsa e erro relativo | pendente (Fase 3) |

## Como rodar

Requer Icarus Verilog, Python 3 e make (Verilator e Yosys são opcionais).
Ubuntu/WSL: `sudo apt install iverilog python3 verilator yosys make`. macOS: `brew install icarus-verilog verilator yosys`.

```bash
make test     # decodificador, codificador, ALU e unidade vetorial (T8, T16, T32)
make lint     # Verilator -Wall
make synth    # Yosys: células/LUT6 por módulo e tamanho
```

Código em `rtl/`; testbenches, oráculo Python e gerador de vetores em `tb/`.
A ALU é verificada contra `tb/takum_oracle.py`, que usa aritmética exata com `Fraction` e não compartilha código com o RTL.
