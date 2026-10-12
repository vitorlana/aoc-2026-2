// =============================================================================
// takum_encoder.v — Codificador de takum LINEAR de N bits
// -----------------------------------------------------------------------------
// Projeto Integrador AOC 2026/02 — Fase 1
//
// Recebe um valor no formato interno ALARGADO (o que a soma/multiplicação
// vai produzir) e devolve a palavra takum de N bits, ARREDONDADA e SATURADA.
//
//   valor = (-1)^sign * (1 + frac / 2^(N-3) [+ algo menor, se sticky]) * 2^exp
//
//   is_zero, is_nar  casos especiais (têm prioridade sobre tudo)
//   sign             sinal
//   exp              expoente com sinal, 11 bits (pode estar fora de -255..254:
//                    a multiplicação soma expoentes)
//   frac             N-3 bits: N-5 bits de fração + bit guard + bit round
//   sticky           OU de todos os bits que o núcleo já descartou abaixo de frac
//
// Etapas:
//   1. faixa: exp > 254 -> maior positivo ; exp < -255 -> menor positivo
//   2. D, r, R, C a partir de exp (inverso do takum_hdr_dec):
//        D = 1:  a = exp + 1 ; r = posição do 1 mais significativo de a ;
//                C = os r bits de a abaixo desse 1 ;  R = r
//        D = 0:  a = -exp    ; r = idem ;  C = esses bits INVERTIDOS ; R = ~r
//   3. monta a palavra longa  0 | D | R | C (r bits) | frac
//   4. arredonda para o mais próximo, empate para o par, NA PALAVRA:
//        guard = 1º bit descartado ; sticky = OU dos demais (e do sticky de entrada)
//        soma 1 se guard & (sticky | lsb)
//      Funciona porque o takum é monótono: o inteiro seguinte é o takum
//      seguinte, então o vai-um ajusta C, R e D sozinho (Hunhold, Alg. 1).
//   5. satura: resultado 0 -> menor positivo ; vai-um no bit de sinal -> maior
//   6. se sign = 1, complemento de 2
//
// Parâmetro: N >= 8 (testado com 8, 16 e 32).
// =============================================================================
`timescale 1ns/1ps

module takum_encoder #(
    parameter N = 16
) (
    input  wire               is_zero,
    input  wire               is_nar,
    input  wire               sign,
    input  wire signed [10:0] exp,
    input  wire [N-4:0]       frac,     // N-3 bits
    input  wire               sticky,
    output wire [N-1:0]       t
);
    localparam [N-1:0] MAXPOS = {1'b0, {(N-1){1'b1}}};   // 0111...1
    localparam [N-1:0] MINPOS = {{(N-1){1'b0}}, 1'b1};   // 0000...1
    localparam [N-1:0] NAR    = {1'b1, {(N-1){1'b0}}};   // 1000...0

    // ---- 1. faixa do expoente ----------------------------------------------
    wire too_big   = (exp >  11'sd254);
    wire too_small = (exp < -11'sd255);

    // ---- 2. D, r, R, C ------------------------------------------------------
    wire        d = ~exp[10];                               // exp >= 0
    /* verilator lint_off UNUSEDSIGNAL */  // na faixa válida, a cabe em 8 bits
    wire [10:0] a_wide = d ? (exp + 11'sd1) : (-exp);       // 1 .. 255 na faixa
    /* verilator lint_on UNUSEDSIGNAL */
    wire [7:0]  a = a_wide[7:0];

    // priority encoder 8 -> 3: posição do bit 1 mais significativo de a
    reg [2:0] r;
    always @* begin
        casez (a)
            8'b1???????: r = 3'd7;
            8'b01??????: r = 3'd6;
            8'b001?????: r = 3'd5;
            8'b0001????: r = 3'd4;
            8'b00001???: r = 3'd3;
            8'b000001??: r = 3'd2;
            8'b0000001?: r = 3'd1;
            default:     r = 3'd0;
        endcase
    end

    wire [6:0] mask   = (7'd1 << r) - 7'd1;                 // r bits em 1
    wire [6:0] c_bits = (d ? a[6:0] : ~a[6:0]) & mask;      // C alinhado à direita
    wire [2:0] reg_r  = d ? r : ~r;

    // ---- 3. palavra longa ---------------------------------------------------
    // {C (7 bits), frac} << (7 - r) coloca os r bits de C no topo e a fração
    // logo depois, qualquer que seja r.
    localparam BW = 7 + (N - 3);                            // largura do corpo
    wire [BW-1:0] body = {c_bits, frac} << (3'd7 - r);

    // full = 0 | D | R(3) | body  -> N + 9 bits
    wire [N+8:0] full = {1'b0, d, reg_r, body};

    // ---- 4. arredondamento (RNE na palavra) ---------------------------------
    wire [N-1:0] w     = full[N+8:9];                       // N bits de cima
    wire         guard = full[8];
    wire         stk   = (|full[7:0]) | sticky;
    wire         rnd   = guard & (stk | w[0]);
    wire [N-1:0] w_rnd = w + {{(N-1){1'b0}}, rnd};

    // ---- 5. saturação --------------------------------------------------------
    reg [N-1:0] mag;
    always @* begin
        if (too_big)              mag = MAXPOS;
        else if (too_small)       mag = MINPOS;
        else if (w_rnd[N-1])      mag = MAXPOS;   // vai-um chegou ao sinal
        else if (w_rnd == {N{1'b0}}) mag = MINPOS; // nunca vira zero
        else                      mag = w_rnd;
    end

    // ---- 6. sinal e casos especiais ------------------------------------------
    wire [N-1:0] signed_word = sign ? (~mag + 1'b1) : mag;

    assign t = is_nar  ? NAR :
               is_zero ? {N{1'b0}} :
                         signed_word;
endmodule
