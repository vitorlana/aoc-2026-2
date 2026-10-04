// =============================================================================
// takum_decoder.v — Decodificador de takum LINEAR de N bits
// -----------------------------------------------------------------------------
// Projeto Integrador AOC 2026/02 — Fase 1
//
// Converte a palavra takum t[N-1:0] para o FORMATO INTERNO (sinal-magnitude):
//
//     valor = (-1)^sign * (1 + frac / 2^(N-5)) * 2^exp
//
//   is_zero  1 se t == 000...0
//   is_nar   1 se t == 100...0   (Not a Real)
//   sign     sinal
//   exp      expoente com sinal, 9 bits, de -255 a +254
//   frac     fração com N-5 bits ALINHADA À ESQUERDA (bit N-6 vale 1/2).
//            Um takum tem p = N-5-r bits de fração; os bits que ele não tem
//            saem como zero.
//   Para zero e NaR: sign = 0, exp = 0, frac = 0 (use as flags).
//
// Caminho de dados (combinacional):
//   1. detecta zero e NaR
//   2. se t é negativo, nega a palavra (complemento de 2). Pela Prop. 6 de
//      Hunhold, valor(-t) = -valor(t), então basta decodificar positivos.
//   3. cabeçalho de 12 bits (completado com zeros se N < 12: ghost bits)
//      -> takum_hdr_dec -> r, exp
//   4. fração: desloca a palavra (5 + r) bits para a esquerda e pega os
//      N-5 bits de cima. O deslocamento tem só 8 valores (r = 0..7).
//
// Parâmetro: N >= 8 (testado com 8, 16 e 32).
// =============================================================================
`timescale 1ns/1ps

module takum_decoder #(
    parameter N = 16
) (
    input  wire [N-1:0]      t,
    output wire              is_zero,
    output wire              is_nar,
    output wire              sign,
    output wire signed [8:0] exp,
    output wire [N-6:0]      frac
);
    // ---- 1. casos especiais ------------------------------------------------
    wire rest_zero = ~|t[N-2:0];
    assign is_zero = ~t[N-1] & rest_zero;
    assign is_nar  =  t[N-1] & rest_zero;
    wire   special = rest_zero;               // zero ou NaR

    // ---- 2. negação condicional (u é sempre positivo) ----------------------
    wire [N-1:0] u = t[N-1] ? (~t + 1'b1) : t;

    // ---- 3. cabeçalho de 12 bits --------------------------------------------
    wire [11:0] h;
    generate
        if (N >= 12) begin : g_hdr_wide
            assign h = u[N-1 -: 12];
        end else begin : g_hdr_ghost
            // ghost bits: os bits que faltam valem zero
            assign h = {u, {(12-N){1'b0}}};
        end
    endgenerate

    wire [2:0]        r;
    wire signed [8:0] exp_raw;
    takum_hdr_dec u_hdr (.h(h), .r(r), .exp(exp_raw));

    // ---- 4. fração ----------------------------------------------------------
    // A fração começa logo depois de S(1) D(1) R(3) C(r): posição 5 + r.
    wire [3:0]   shamt   = 4'd5 + {1'b0, r};  // 5 .. 12
    /* verilator lint_off UNUSEDSIGNAL */  // os 5 bits de baixo nunca são usados
    wire [N-1:0] shifted = u << shamt;        // bits que "saem" viram zero
    /* verilator lint_on UNUSEDSIGNAL */
    wire [N-6:0] frac_raw = shifted[N-1 -: N-5];

    // ---- saídas -------------------------------------------------------------
    assign sign = special ? 1'b0 : t[N-1];
    assign exp  = special ? 9'sd0 : exp_raw;
    assign frac = special ? {(N-5){1'b0}} : frac_raw;
endmodule
