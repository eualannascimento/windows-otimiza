<#
  otimiza_windows.ps1
  Diagnostica e (opcionalmente) aplica otimizacoes seguras de performance
  em notebook Windows corporativo, SEM privilegios de administrador.

  Escopo deliberado:
    - So mexe em HKCU (configuracao do usuario atual) e em arquivos que
      pertencem ao proprio usuario (temp, cache de navegador).
    - NUNCA toca em antivirus/EDR/VPN/agentes de gestao corporativa
      (lista de exclusao abaixo) - alterar isso pode violar politica de
      seguranca da empresa e nao e o objetivo aqui.
    - Tudo que for alterado fica registrado em revert_log.txt, com o
      valor original, para poder desfazer manualmente se necessario.

  Uso:
    Diagnostico apenas (nao muda nada):
      powershell -ExecutionPolicy Bypass -File .\otimiza_windows.ps1

    Diagnostico + aplicar otimizacoes seguras:
      powershell -ExecutionPolicy Bypass -File .\otimiza_windows.ps1 -Apply

  Se algo falhar por falta de permissao (GPO bloqueando usuario padrao),
  o script apenas registra "bloqueado por politica" e segue em frente -
  isso por si so e um dado util (mostra o que a TI trava).
#>

param(
    [switch]$Apply
)

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = "diagnostico_$stamp.txt"
$revertFile = "revert_log_$stamp.txt"

# Palavras-chave de software corporativo/seguranca que NUNCA sao tocadas
$protectedKeywords = @(
    'crowdstrike','defender','sentinelone','sentinel','cylance','carbonblack','carbon black',
    'tanium','ivanti','bigfix','mcafee','symantec','sophos','trendmicro','trend micro',
    'globalprotect','anyconnect','cisco','zscaler','forcepoint','netskope','vpn',
    'bitlocker','intune','sccm','configmgr','jamf','airwatch','workspace one','citrix',
    'onedrive' # OneDrive so recebe recomendacao de pausa, nunca remocao de startup
)

function Write-Report($text) {
    $text | Out-File $reportFile -Append -Encoding UTF8
}
function Write-Revert($text) {
    $text | Out-File $revertFile -Append -Encoding UTF8
}
function Is-Protected($text) {
    foreach ($kw in $protectedKeywords) {
        if ($text -match [regex]::Escape($kw)) { return $true }
    }
    return $false
}

"=== DIAGNOSTICO E OTIMIZACAO WINDOWS - $(Get-Date) ===" | Out-File $reportFile -Encoding UTF8
"Modo: $(if ($Apply) {'DIAGNOSTICO + APLICACAO'} else {'SOMENTE DIAGNOSTICO (rode com -Apply para aplicar)'})" | Out-File $reportFile -Append
"=== LOG DE REVERSAO - $(Get-Date) ===" | Out-File $revertFile -Encoding UTF8

# --------------------------------------------------------------------
# 1. DIAGNOSTICO
# --------------------------------------------------------------------

Write-Report "`n--- SISTEMA ---"
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture, LastBootUpTime, FreePhysicalMemory, TotalVisibleMemorySize | Format-List | Out-String | Write-Report

Write-Report "`n--- HARDWARE ---"
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, TotalPhysicalMemory | Format-List | Out-String | Write-Report
Get-CimInstance Win32_Processor | Select-Object Name, LoadPercentage, MaxClockSpeed, CurrentClockSpeed | Format-List | Out-String | Write-Report

Write-Report "`n--- DISCO ---"
Get-PSDrive -PSProvider FileSystem | Select-Object Name, @{N='UsedGB';E={[math]::Round($_.Used/1GB,1)}}, @{N='FreeGB';E={[math]::Round($_.Free/1GB,1)}} | Format-Table | Out-String | Write-Report

Write-Report "`n--- TOP 15 PROCESSOS POR MEMORIA ---"
Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 15 Name, Id, @{N='RAM_MB';E={[math]::Round($_.WorkingSet/1MB,1)}} | Format-Table | Out-String | Write-Report

Write-Report "`n--- PROGRAMAS DE INICIALIZACAO (usuario) ---"
$startupItems = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
$startupItems | Format-Table -Wrap | Out-String | Write-Report

Write-Report "`n--- HISTORICO DE CONFIABILIDADE (ultimos 20 - crashes/travamentos) ---"
try {
    Get-CimInstance Win32_ReliabilityRecords -ErrorAction Stop | Sort-Object TimeGenerated -Descending | Select-Object -First 20 TimeGenerated, SourceName, Message | Format-Table -Wrap | Out-String | Write-Report
} catch {
    Write-Report "Nao foi possivel ler o historico de confiabilidade: $_"
}

Write-Report "`n--- TAMANHO DE PASTAS TEMPORARIAS/CACHE (candidatas a limpeza) ---"
$cleanupTargets = @(
    "$env:TEMP",
    "$env:LOCALAPPDATA\Temp",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" # thumbnail cache
)
foreach ($p in $cleanupTargets) {
    if (Test-Path $p) {
        $size = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round(($size / 1MB), 1)
        Write-Report "$p -> $sizeMB MB"
    }
}

# --------------------------------------------------------------------
# 2. APLICACAO DE OTIMIZACOES SEGURAS (so roda com -Apply)
# --------------------------------------------------------------------

if ($Apply) {
    Write-Report "`n=== APLICANDO OTIMIZACOES ==="

    # 2.1 Limpeza de temp/cache do proprio usuario (seguro, tudo regenera)
    Write-Report "`n--- Limpando temp e cache ---"
    $freedTotalMB = 0
    foreach ($p in @("$env:TEMP", "$env:LOCALAPPDATA\Temp")) {
        if (Test-Path $p) {
            $before = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            $after = if (Test-Path $p) { (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } else { 0 }
            $freedMB = [math]::Round((($before - $after) / 1MB), 1)
            $freedTotalMB += $freedMB
            Write-Report "Limpo: $p (~$freedMB MB liberados)"
        }
    }
    Write-Report "Total liberado em temp: ~$freedTotalMB MB"
    Write-Revert "Limpeza de temp nao e reversivel (arquivos temporarios), mas sao recriados normalmente pelo Windows/apps sem perda funcional."

    # 2.2 Esvaziar lixeira do usuario
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Report "Lixeira esvaziada."
    } catch {
        Write-Report "Nao foi possivel esvaziar a lixeira: $_"
    }

    # 2.3 Ajustar efeitos visuais para performance (HKCU - reversivel)
    Write-Report "`n--- Ajustando efeitos visuais para performance ---"
    try {
        $vfxPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $vfxPath)) { New-Item -Path $vfxPath -Force | Out-Null }
        $currentVal = (Get-ItemProperty -Path $vfxPath -Name VisualFXSetting -ErrorAction SilentlyContinue).VisualFXSetting
        Write-Revert "VisualFXSetting original: $currentVal (registry: $vfxPath). Para reverter: Set-ItemProperty -Path '$vfxPath' -Name VisualFXSetting -Value $currentVal"
        Set-ItemProperty -Path $vfxPath -Name VisualFXSetting -Value 2 -Type DWord
        Write-Report "VisualFXSetting definido para 'Ajustar para melhor performance' (2)."
    } catch {
        Write-Report "Nao foi possivel ajustar efeitos visuais (pode estar bloqueado por politica corporativa): $_"
    }

    # 2.4 Desabilitar (nao deletar) itens de inicializacao nao-essenciais do usuario
    Write-Report "`n--- Revisando itens de inicializacao (HKCU Run) ---"
    $runPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $runPath) {
        $runItems = Get-Item $runPath | Select-Object -ExpandProperty Property
        foreach ($name in $runItems) {
            $value = (Get-ItemProperty -Path $runPath -Name $name).$name
            if (Is-Protected("$name $value")) {
                Write-Report "MANTIDO (protegido/corporativo): $name -> $value"
                continue
            }
            # Move para uma chave de backup em vez de apagar - 100% reversivel
            $backupPath = "HKCU:\Software\otimiza_windows_backup_run"
            if (-not (Test-Path $backupPath)) { New-Item -Path $backupPath -Force | Out-Null }
            Set-ItemProperty -Path $backupPath -Name $name -Value $value -Force
            Remove-ItemProperty -Path $runPath -Name $name -ErrorAction SilentlyContinue
            Write-Report "DESABILITADO: $name -> $value (movido para backup)"
            Write-Revert "Para reativar '$name': Set-ItemProperty -Path '$runPath' -Name '$name' -Value '$value'"
        }
    }

    # 2.5 Pasta de inicializacao (atalhos) - move para subpasta, nao apaga
    Write-Report "`n--- Revisando pasta de Inicializacao (atalhos) ---"
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $disabledFolder = Join-Path $startupFolder "Desabilitados_por_otimiza_windows"
    if (-not (Test-Path $disabledFolder)) { New-Item -Path $disabledFolder -ItemType Directory -Force | Out-Null }
    Get-ChildItem $startupFolder -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
        if (Is-Protected($_.Name)) {
            Write-Report "MANTIDO (protegido/corporativo): $($_.Name)"
        } else {
            Move-Item $_.FullName -Destination $disabledFolder -Force
            Write-Report "DESABILITADO (atalho movido): $($_.Name)"
            Write-Revert "Para reativar: mover '$($_.Name)' de volta de '$disabledFolder' para '$startupFolder'"
        }
    }

    # 2.6 Storage Sense (limpeza automatica) - so aplica se a chave for acessivel sem admin
    Write-Report "`n--- Habilitando Storage Sense ---"
    try {
        $ssPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
        if (-not (Test-Path $ssPath)) { New-Item -Path $ssPath -Force | Out-Null }
        Set-ItemProperty -Path $ssPath -Name "01" -Value 1 -Type DWord -ErrorAction Stop
        Write-Report "Storage Sense habilitado."
        Write-Revert "Para desativar Storage Sense: Set-ItemProperty -Path '$ssPath' -Name '01' -Value 0"
    } catch {
        Write-Report "Nao foi possivel habilitar Storage Sense (provavel bloqueio por politica): $_"
    }

    # 2.7 Plano de energia - tenta alto desempenho/equilibrado (falha graciosamente se GPO bloquear)
    Write-Report "`n--- Verificando plano de energia ---"
    try {
        $plans = powercfg /list 2>&1
        Write-Report ($plans | Out-String)
        Write-Report "Se a TI permitir, use 'powercfg /setactive <GUID>' para trocar de plano manualmente."
    } catch {
        Write-Report "Nao foi possivel consultar planos de energia: $_"
    }

    Write-Report "`n=== APLICACAO CONCLUIDA. Reinicie o notebook para os efeitos completos. ==="
} else {
    Write-Report "`n(Nada foi alterado - rode novamente com -Apply para aplicar as otimizacoes seguras.)"
}

Write-Host "Concluido."
Write-Host "Relatorio: $reportFile"
if ($Apply) { Write-Host "Log de reversao: $revertFile" }
