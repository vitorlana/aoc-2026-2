# aoc-2026-2

Projeto Integrador AOC 2026/02 — Formato aritmético Takum na Extensão Vetorial RISC-V (RVV).

## Documentação

- [Fase 1 — Revisão bibliográfica (HTML interativo)](docs/revisao-bibliografica.html) · [versão Markdown](docs/01-revisao-bibliografica.md)
- [Fase 1 — Guia do decodificador e codificador em Verilog](docs/02-fase1-decoder-encoder.md)
- [Fase 1 — Implementação: detalhes do código e como rodar](docs/03-fase1-implementacao.md)
- Enunciado: `ProjectGuidelinesAOC.pdf`
- Artigos e livros de referência: `papers/`

## Fase 1 em 30 segundos

Requer Icarus Verilog e make (Verilator e Yosys são opcionais). Ubuntu/WSL:
`sudo apt install iverilog verilator yosys make`.

```bash
make test     # testbenches do decodificador e do codificador takum (T8, T16, T32)
make lint     # Verilator -Wall
make synth    # Yosys: células/LUT6 por módulo e tamanho
```

Código em `rtl/`, testbenches e modelo de referência em `tb/`. Detalhes em
[`docs/03-fase1-implementacao.md`](docs/03-fase1-implementacao.md).
