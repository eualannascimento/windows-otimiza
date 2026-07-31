# Validação em máquina virtual

Execute primeiro em uma VM Windows com snapshot. Confirme que o modo diagnóstico não altera registro nem inicialização, que -Apply só altera HKCU e caminhos do usuário, que agentes corporativos permanecem intactos e que o log JSONL contém timestamp, ação e escopo. Teste também a restauração dos valores originais.

A validação em VM não foi executada neste ambiente.
