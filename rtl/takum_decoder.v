// takum_decoder.v — Decodificador de takum linear de N bits

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
    // ---- casos especiais ------------------------------------------------
    wire rest_zero = ~|t[N-2:0];
    assign is_zero = ~t[N-1] & rest_zero;
    assign is_nar  =  t[N-1] & rest_zero;
    wire   special = rest_zero;               // zero ou NaR

    // ---- negação condicional ----------------------------------------------
    wire [N-1:0] u = t[N-1] ? (~t + 1'b1) : t;

    // ---- cabeçalho de 12 bits --------------------------------------------
    wire [11:0] h;
    generate
        if (N >= 12) begin : g_hdr_wide
            assign h = u[N-1 -: 12];
        end else begin : g_hdr_ghost
            // bits que faltam valem zero
            assign h = {u, {(12-N){1'b0}}};
        end
    endgenerate

    wire [2:0]        r;
    wire signed [8:0] exp_raw;
    takum_hdr_dec u_hdr (.h(h), .r(r), .exp(exp_raw));

    // ---- fração --------- (A fração começa logo depois de S(1) D(1) R(3) C(r): posição 5 + r.) -----
    wire [3:0]   shamt   = 4'd5 + {1'b0, r};  // 5 .. 12
    /* verilator lint_off UNUSEDSIGNAL */  // os 5 bits de baixo nunca são usados
    wire [N-1:0] shifted = u << shamt;        // bits que saem viram zero
    /* verilator lint_on UNUSEDSIGNAL */
    wire [N-6:0] frac_raw = shifted[N-1 -: N-5];

    // ---- saídas -------------------------------------------------------------
    assign sign = special ? 1'b0 : t[N-1];
    assign exp  = special ? 9'sd0 : exp_raw;
    assign frac = special ? {(N-5){1'b0}} : frac_raw;
endmodule
