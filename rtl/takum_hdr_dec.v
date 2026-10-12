// =============================================================================
// takum_hdr_dec.v — Decodificador do cabeçalho de 12 bits de um takum LINEAR
// -----------------------------------------------------------------------------
// Projeto Integrador AOC 2026/02 — Fase 1
//
// Recebe os 12 bits mais significativos de um takum POSITIVO (S = 0) e devolve
// o número de bits de característica r e o expoente e (= característica c).
//
//   h[11]    S  (ignorado: o chamador já negou a palavra se ela era negativa)
//   h[10]    D  direção  (1: |x| >= 1, 0: |x| < 1)
//   h[9:7]   R  regime   (3 bits)
//   h[6:0]   janela onde ficam os r bits de característica C (alinhados à esq.)
//
// Fórmulas (Hunhold 2024, Def. 8), reescritas para hardware:
//   r = D ? R : 7 - R            7 - R em 3 bits = inverter os bits de R
//   C = h[6:0] >> (7 - r)        os r bits de cima da janela
//   D = 1:  c = 2^r - 1 + C      =  {1, C} - 1          (0 ... 254)
//   D = 0:  c = -2^(r+1) + 1 + C = -{1, ~C}             (-255 ... -1)
// onde {1, C} é o número formado por um bit 1 seguido dos r bits de C.
//
// Este módulo NÃO depende de N: é o mesmo para T8, T16, T32 (e T64).
// É a afirmação central do takum: um único decodificador de 12 bits.
// =============================================================================
`timescale 1ns/1ps

module takum_hdr_dec (
    /* verilator lint_off UNUSEDSIGNAL */  // h[11] (S) é ignorado de propósito
    input  wire [11:0]       h,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [2:0]        r,      // nº de bits de característica (0..7)
    output wire signed [8:0] exp     // expoente e = c, de -255 a +254
);
    wire       d     = h[10];
    wire [2:0] reg_r = h[9:7];

    // r = D ? R : 7 - R   (7 - R == ~R em 3 bits)
    assign r = d ? reg_r : ~reg_r;

    // C: r bits alinhados à direita (0 .. 2^r - 1)
    wire [6:0] c_bits = h[6:0] >> (3'd7 - r);

    // máscara com r bits em 1, e o "1 implícito" na posição r
    wire [7:0] mask = (8'd1 << r) - 8'd1;
    wire [7:0] one  =  8'd1 << r;

    // {1, C} e {1, ~C}  (8 bits, valores 1 .. 255)
    wire [7:0] a_pos = one | {1'b0, c_bits};
    wire [7:0] a_neg = one | (~{1'b0, c_bits} & mask);

    assign exp = d ? $signed({1'b0, a_pos}) - 9'sd1
                   : -$signed({1'b0, a_neg});
endmodule
