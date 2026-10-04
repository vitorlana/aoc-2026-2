// =============================================================================
// tb_roundtrip.v — Ida e volta: encoder(decoder(t)) == t
//   Não precisa de modelo: é o RTL contra ele mesmo. Pega a maioria dos erros
//   de campo nos dois módulos.
//   T8 e T16: todos os padrões.  T32: N32 aleatórios (padrão 200000).
// =============================================================================
`timescale 1ns/1ps
module rt_check #(parameter N = 16, parameter SEED = 1) ();
    reg  [N-1:0]      t;
    wire              is_zero, is_nar, sign;
    wire signed [8:0] exp;
    wire [N-6:0]      frac;
    wire [N-1:0]      t_back;

    takum_decoder #(.N(N)) dec (.t(t), .is_zero(is_zero), .is_nar(is_nar),
                                .sign(sign), .exp(exp), .frac(frac));

    // formato interno -> entrada do encoder: expoente com extensão de sinal,
    // fração com guard = round = 0, sticky = 0 (nada a arredondar)
    takum_encoder #(.N(N)) enc (.is_zero(is_zero), .is_nar(is_nar), .sign(sign),
                                .exp({{2{exp[8]}}, exp}), .frac({frac, 2'b00}),
                                .sticky(1'b0), .t(t_back));

    integer errors = 0, checks = 0;
    reg done = 0;

    task check_one;
        input [N-1:0] x;
        begin
            t = x; #1; checks = checks + 1;
            if (t_back !== x) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("ERRO T%0d t=%h -> sign=%b exp=%0d frac=%h -> %h", N, x, sign, exp, frac, t_back);
            end
        end
    endtask

    integer i, count, seed;
    reg [31:0] rnd;
    initial begin
        seed = SEED;
        if (N <= 16) begin
            for (i = 0; i < (1 << N); i = i + 1) check_one(i);
        end else begin
            if (!$value$plusargs("N32=%d", count)) count = 200000;
            for (i = 0; i < count; i = i + 1) begin
                rnd = $random(seed);
                check_one(rnd[N-1:0]);
            end
        end
        if (errors == 0) $display("PASS roundtrip T%0d: %0d padrões", N, checks);
        else             $display("FAIL roundtrip T%0d: %0d erros em %0d padrões", N, errors, checks);
        done = 1;
    end
endmodule

module tb_roundtrip;
    rt_check #(.N(8),  .SEED(101)) c8  ();
    rt_check #(.N(16), .SEED(202)) c16 ();
    rt_check #(.N(32), .SEED(303)) c32 ();
    initial begin
        wait (c8.done && c16.done && c32.done);
        $finish;
    end
endmodule
