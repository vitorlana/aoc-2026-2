# Lê a saída de 'stat' do Yosys e imprime o nº de células lógicas.
# Funciona com o formato antigo ("Number of cells: N") e com o novo ("N cells").
/Number of cells/            { c = $4 }
/^ +[0-9]+ +cells$/          { c = $1 }
/\$scopeinfo/                { s = $1 }
END                          { print c - s }
