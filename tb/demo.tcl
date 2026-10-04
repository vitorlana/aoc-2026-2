# Script do GTKWave para a demonstração (tb_demo.v)
#   gtkwave build/demo.vcd -S tb/demo.tcl
# Adiciona os sinais em grupos, escolhe formatos e ajusta o zoom.

proc add {sigs fmt} {
    gtkwave::addSignalsFromList $sigs
    gtkwave::highlightSignalsFromList $sigs
    gtkwave::/Edit/Data_Format/$fmt
    gtkwave::/Edit/UnHighlight_All
}

add {tb_demo.caso[192:1]} ASCII
gtkwave::/Edit/Insert_Comment "Parte 1: decoder -> encoder (T8)"
add {tb_demo.t[7:0]} Hex
add {tb_demo.h[11:0]} Binary
add {tb_demo.r[2:0]} Decimal
add {tb_demo.is_zero tb_demo.is_nar tb_demo.sign} Hex
add {tb_demo.exp[8:0]} Signed_Decimal
add {tb_demo.frac[2:0]} Binary
add {tb_demo.t_back[7:0]} Hex
gtkwave::/Edit/Insert_Comment "Parte 2: encoder com arredondamento"
add {tb_demo.e_sign tb_demo.e_sticky} Hex
add {tb_demo.e_exp[10:0]} Signed_Decimal
add {tb_demo.e_frac[4:0]} Binary
add {tb_demo.guard tb_demo.rnd} Hex
add {tb_demo.e_t[7:0]} Hex

gtkwave::setZoomFactor -3
gtkwave::/Time/Zoom/Zoom_Full
