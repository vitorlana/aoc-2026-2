// tb_decoder.v — Verifica takum_decoder para N = 8, 16 e 32

`timescale 1ns/1ps
module dec_check #(parameter N = 16, parameter SEED = 1) ();
    `include "takum_ref.vh"

    reg  [N-1:0]      t;
    wire              is_zero, is_nar, sign;
    wire signed [8:0] exp;
    wire [N-6:0]      frac;

    takum_decoder #(.N(N)) dut (.t(t), .is_zero(is_zero), .is_nar(is_nar),
                                .sign(sign), .exp(exp), .frac(frac));

    integer errors = 0, checks = 0;
    reg done = 0;

    task check_one;
        input [N-1:0] x;
        real want, got;
        reg  want_zero, want_nar;
        begin
            t = x; #1;
            checks    = checks + 1;
            want_zero = (x == 0);
            want_nar  = ref_is_nar(x, N);
            want      = ref_value(x, N);
            got       = unpacked_value(sign, exp, frac, N-5);
            if (is_zero !== want_zero || is_nar !== want_nar ||
                (!want_zero && !want_nar && got != want)) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("ERRO T%0d t=%h: zero=%b nar=%b sign=%b exp=%0d frac=%h -> %e | esperado zero=%b nar=%b valor=%e",
                             N, x, is_zero, is_nar, sign, exp, frac, got, want_zero, want_nar, want);
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
            // bordas
            check_one({N{1'b0}});                       // zero
            check_one({1'b1, {(N-1){1'b0}}});           // NaR
            check_one({2'b01, {(N-2){1'b0}}});          // 1
            check_one({2'b11, {(N-2){1'b0}}});          // -1
            check_one({1'b0, {(N-1){1'b1}}});           // maior positivo
            check_one({{(N-1){1'b0}}, 1'b1});           // menor positivo
            check_one({N{1'b1}});                       // maior negativo
            check_one({1'b1, {(N-2){1'b0}}, 1'b1});     // menor negativo
            for (i = 0; i < count; i = i + 1) begin
                rnd = $random(seed);
                check_one(rnd[N-1:0]);
            end
        end
        if (errors == 0) $display("PASS decoder T%0d: %0d padrões", N, checks);
        else             $display("FAIL decoder T%0d: %0d erros em %0d padrões", N, errors, checks);
        done = 1;
    end
endmodule

module tb_decoder;
    dec_check #(.N(8),  .SEED(11)) c8  ();
    dec_check #(.N(16), .SEED(22)) c16 ();
    dec_check #(.N(32), .SEED(33)) c32 ();
    initial begin
        wait (c8.done && c16.done && c32.done);
        $finish;
    end
endmodule
