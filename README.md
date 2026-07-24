# windows-otimiza

Scripts PowerShell para diagnosticar e otimizar performance de notebooks Windows
corporativos, **sem exigir privilégios de administrador**. Feitos para o cenário
de usuário padrão (não-admin) em máquina gerenciada por TI (Intune/GPO), como um
Lenovo ThinkPad T14.

## Scripts

### `diagnostico_windows.ps1`
Somente coleta informações (não altera nada): CPU/RAM/disco, processos mais
pesados, itens de inicialização, serviços de terceiros, histórico de
travamentos (Reliability Monitor), throttling térmico e updates pendentes.
Gera `diagnostico_saida.txt`.

### `otimiza_windows.ps1`
Diagnostica e, opcionalmente, aplica otimizações seguras e reversíveis:

```powershell
# Somente diagnóstico (não muda nada)
powershell -ExecutionPolicy Bypass -File .\otimiza_windows.ps1

# Diagnóstico + aplicar otimizações
powershell -ExecutionPolicy Bypass -File .\otimiza_windows.ps1 -Apply
```

O que é alterado com `-Apply`:
- Limpa temp/cache do próprio usuário e lixeira.
- Ajusta efeitos visuais para performance (reversível via registro HKCU).
- Desabilita itens de inicialização não-essenciais movendo-os para backup
  (não apaga nada — 100% reversível).
- Habilita Storage Sense (limpeza automática de espaço).

Gera `revert_log_*.txt` com o passo a passo para desfazer cada alteração.

## O que o script propositalmente NÃO toca

Antivírus/EDR, VPN corporativa, agentes de gestão (Intune, Citrix, SCCM,
Tanium, etc.) e OneDrive nunca são desabilitados ou alterados — uma lista de
palavras-chave protegidas (`$protectedKeywords` em `otimiza_windows.ps1`)
garante isso. Mexer nessas ferramentas é decisão da TI, não do script.

Se alguma ação for bloqueada por política de grupo (GPO), o script registra
isso no relatório e segue em frente, sem tentar contornar a restrição.

## Aviso

Rode primeiro sem `-Apply` para revisar o diagnóstico antes de aplicar
qualquer mudança. Sempre guarde o `revert_log_*.txt` gerado.
