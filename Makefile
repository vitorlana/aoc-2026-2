# =============================================================================
# Projeto Integrador AOC 2026/02 — Fase 1: decodificador e codificador takum
# -----------------------------------------------------------------------------
#   make test        roda todos os testbenches (Icarus Verilog)
#   make ref         só o teste do modelo de referência
#   make decoder     só o decodificador
#   make encoder     só o codificador
#   make roundtrip   só a ida e volta
#   make lint        Verilator --lint-only -Wall para N = 8, 16, 32
#   make synth       Yosys: células genéricas e LUT6 para N = 8, 16, 32
#   make demo        simula tb_demo e grava build/demo.vcd (formas de onda)
#   make waves       make demo + abre no GTKWave já com os sinais arrumados
#   make schematic   desenha o circuito (Yosys + netlistsvg, ou Graphviz) em build/sch/
#   make clean       apaga build/
#
#   Mais casos aleatórios:  make test N32=1000000 NENC=500000
# =============================================================================

IVERILOG ?= iverilog
VVP      ?= vvp
VERILATOR?= verilator
YOSYS    ?= yosys

BUILD    := build
RTL      := rtl/takum_hdr_dec.v rtl/takum_decoder.v rtl/takum_encoder.v
TBDIR    := tb
SIZES    := 8 16 32

N32      ?= 200000
NENC     ?= 100000

IVFLAGS  := -g2005 -Wall -I $(TBDIR)

.PHONY: all test ref decoder encoder roundtrip lint synth demo waves schematic clean

all: test

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/%.vvp: $(TBDIR)/%.v $(TBDIR)/takum_ref.vh $(RTL) | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -o $@ $< $(RTL)

ref: $(BUILD)/tb_ref.vvp
	$(VVP) -n $< | grep -E "PASS|FAIL|ERRO"

decoder: $(BUILD)/tb_decoder.vvp
	$(VVP) -n $< +N32=$(N32) | grep -E "PASS|FAIL|ERRO"

roundtrip: $(BUILD)/tb_roundtrip.vvp
	$(VVP) -n $< +N32=$(N32) | grep -E "PASS|FAIL|ERRO"

encoder: $(BUILD)/tb_encoder.vvp
	$(VVP) -n $< +NENC=$(NENC) | grep -E "PASS|FAIL|ERRO"

test: $(BUILD)/tb_ref.vvp $(BUILD)/tb_decoder.vvp $(BUILD)/tb_roundtrip.vvp $(BUILD)/tb_encoder.vvp
	@( $(VVP) -n $(BUILD)/tb_ref.vvp ; \
	   $(VVP) -n $(BUILD)/tb_decoder.vvp +N32=$(N32) ; \
	   $(VVP) -n $(BUILD)/tb_roundtrip.vvp +N32=$(N32) ; \
	   $(VVP) -n $(BUILD)/tb_encoder.vvp +NENC=$(NENC) ) | tee $(BUILD)/test.log | grep -E "PASS|FAIL|ERRO"
	@if grep -q "FAIL" $(BUILD)/test.log; then echo "==> HÁ FALHAS"; exit 1; \
	 else echo "==> TODOS OS TESTES PASSARAM"; fi

lint:
	@for n in $(SIZES); do \
	  $(VERILATOR) --lint-only -Wall -GN=$$n --top-module takum_decoder rtl/takum_decoder.v rtl/takum_hdr_dec.v && \
	  $(VERILATOR) --lint-only -Wall -GN=$$n --top-module takum_encoder rtl/takum_encoder.v && \
	  echo "lint N=$$n ok" || exit 1; \
	done

# Síntese genérica (sem tecnologia alvo): conta células lógicas e, com
# 'abc -lut 6', LUTs de 6 entradas (aproximação de FPGA). Resultados em build/synth.txt
synth: | $(BUILD)
	@rm -f $(BUILD)/synth.txt
	@for top in takum_hdr_dec takum_decoder takum_encoder; do \
	  for n in $(SIZES); do \
	    if [ $$top = takum_hdr_dec ] && [ $$n != 8 ]; then continue; fi; \
	    if [ $$top = takum_hdr_dec ]; then par=""; label="(12 bits)"; else par="chparam -set N $$n $$top;"; label="N=$$n"; fi; \
	    cells=$$($(YOSYS) -p "read_verilog $(RTL); $$par synth -flatten -top $$top; stat" | awk '/Number of cells/{c=$$4} END{print c}'); \
	    luts=$$($(YOSYS) -p "read_verilog $(RTL); $$par synth -flatten -top $$top; abc -lut 6; opt_clean; stat" | awk '/Number of cells/{c=$$4} END{print c}'); \
	    printf "%-14s %-9s células=%-5s LUT6=%s\n" $$top "$$label" $$cells $$luts | tee -a $(BUILD)/synth.txt; \
	  done; \
	done

# ---- formas de onda ----------------------------------------------------------
GTKWAVE  ?= gtkwave

demo: $(BUILD)/tb_demo.vvp
	$(VVP) -n $< > /dev/null
	@echo "VCD gerado: $(BUILD)/demo.vcd"
	@echo "Abra com:   $(GTKWAVE) $(BUILD)/demo.vcd -S tb/demo.tcl"

waves: demo
	$(GTKWAVE) $(BUILD)/demo.vcd -S tb/demo.tcl &

# ---- esquemáticos -------------------------------------------------------------
# Nível RTL (prep): somadores, deslocadores, muxes e portas, como no código.
# SCH_N escolhe o tamanho (padrão 8, o mais legível).
SCH_N      ?= 8
NETLISTSVG ?= netlistsvg

schematic: | $(BUILD)
	@mkdir -p $(BUILD)/sch
	@for top in takum_hdr_dec takum_decoder takum_encoder; do \
	  if [ $$top = takum_hdr_dec ]; then par=""; else par="chparam -set N $(SCH_N) $$top;"; fi; \
	  if command -v $(NETLISTSVG) >/dev/null; then \
	    $(YOSYS) -q -p "read_verilog $(RTL); $$par prep -top $$top; opt_clean -purge; write_json $(BUILD)/sch/$$top.json" && \
	    $(NETLISTSVG) $(BUILD)/sch/$$top.json -o $(BUILD)/sch/$$top.svg && echo "$(BUILD)/sch/$$top.svg"; \
	  else \
	    $(YOSYS) -q -p "read_verilog $(RTL); $$par prep -top $$top; opt_clean -purge; show -format svg -prefix $(BUILD)/sch/$$top" && \
	    echo "$(BUILD)/sch/$$top.svg (Graphviz; instale netlistsvg para um desenho mais limpo)"; \
	  fi; \
	done

clean:
	rm -rf $(BUILD)
