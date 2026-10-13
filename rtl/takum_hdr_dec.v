// takum_hdr_dec.v — Decodificador do cabeçalho de 12 bits de um takum linear

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
