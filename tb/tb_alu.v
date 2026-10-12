// Testbench da takum_alu: compara o RTL com vetores gerados pelo oráculo Python
// (tb/gen_vectors.py). Formato de cada linha: a b op y (hexadecimal).
`timescale 1ns/1ps
module tb_alu;
    parameter N = 16;
    parameter NV = 1;              // número de vetores
    parameter FILE = "vectors.hex";

    reg  [N-1:0] a, b;
    reg  [1:0]   op;
    wire [N-1:0] y;
    takum_alu #(.N(N)) dut (.a(a), .b(b), .op(op), .y(y));

    reg [N-1:0] va [0:NV-1];
    reg [N-1:0] vb [0:NV-1];
    reg [1:0]   vo [0:NV-1];
    reg [N-1:0] vy [0:NV-1];
    integer fd, i, rc, errors;
    reg [31:0] ta, tb_, to, ty;

    initial begin
        errors = 0;
        fd = $fopen(FILE, "r");
        if (fd == 0) begin $display("ERRO: não abriu %0s", FILE); $finish; end
        i = 0;
        while (!$feof(fd) && i < NV) begin
            rc = $fscanf(fd, "%h %h %h %h\n", ta, tb_, to, ty);
            if (rc == 4) begin va[i] = ta; vb[i] = tb_; vo[i] = to; vy[i] = ty; i = i + 1; end
        end
        $fclose(fd);
        for (i = 0; i < NV; i = i + 1) begin
            a = va[i]; b = vb[i]; op = vo[i];
            #1;
            if (y !== vy[i]) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("ERRO alu T%0d: a=%h b=%h op=%0d obtido=%h esperado=%h", N, a, b, op, y, vy[i]);
            end
        end
        if (errors == 0) $display("PASS alu T%0d: %0d vetores", N, NV);
        else             $display("FAIL alu T%0d: %0d divergências em %0d vetores", N, errors, NV);
        $finish;
    end
endmodule
