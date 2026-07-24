# Diagnóstico de performance - roda como usuário padrão, sem admin
# Uso: abra "Windows PowerShell" (não precisa "Executar como administrador")
#      cd para a pasta onde salvou este arquivo
#      Se der erro de execution policy: powershell -ExecutionPolicy Bypass -File .\diagnostico_windows.ps1
# O resultado sai em diagnostico_saida.txt na mesma pasta - me envie o conteúdo desse arquivo.

$out = "diagnostico_saida.txt"
"=== DIAGNÓSTICO WINDOWS - $(Get-Date) ===" | Out-File $out

"`n--- SISTEMA ---" | Out-File $out -Append
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture, LastBootUpTime, FreePhysicalMemory, TotalVisibleMemorySize | Format-List | Out-File $out -Append

"`n--- HARDWARE ---" | Out-File $out -Append
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, TotalPhysicalMemory, NumberOfLogicalProcessors | Format-List | Out-File $out -Append
Get-CimInstance Win32_Processor | Select-Object Name, LoadPercentage, MaxClockSpeed, CurrentClockSpeed | Format-List | Out-File $out -Append

"`n--- DISCO (espaço livre) ---" | Out-File $out -Append
Get-PSDrive -PSProvider FileSystem | Select-Object Name, @{N='UsedGB';E={[math]::Round($_.Used/1GB,1)}}, @{N='FreeGB';E={[math]::Round($_.Free/1GB,1)}} | Format-Table | Out-File $out -Append

"`n--- TOP 15 PROCESSOS POR CPU ---" | Out-File $out -Append
Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 Name, Id, CPU, @{N='RAM_MB';E={[math]::Round($_.WorkingSet/1MB,1)}} | Format-Table | Out-File $out -Append

"`n--- TOP 15 PROCESSOS POR MEMÓRIA ---" | Out-File $out -Append
Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 15 Name, Id, @{N='RAM_MB';E={[math]::Round($_.WorkingSet/1MB,1)}} | Format-Table | Out-File $out -Append

"`n--- PROGRAMAS DE INICIALIZAÇÃO (usuário) ---" | Out-File $out -Append
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location | Format-Table -Wrap | Out-File $out -Append

"`n--- SERVIÇOS EM EXECUÇÃO (não-Microsoft) ---" | Out-File $out -Append
Get-CimInstance Win32_Service -Filter "State='Running'" | Where-Object { $_.PathName -notlike '*Windows*' } | Select-Object Name, DisplayName, StartMode, PathName | Format-Table -Wrap | Out-File $out -Append

"`n--- HISTÓRICO DE CONFIABILIDADE (últimos 30 eventos - crashes/travamentos) ---" | Out-File $out -Append
try {
    Get-CimInstance Win32_ReliabilityRecords -ErrorAction Stop | Sort-Object TimeGenerated -Descending | Select-Object -First 30 TimeGenerated, SourceName, Message | Format-Table -Wrap | Out-File $out -Append
} catch {
    "Não foi possível ler Win32_ReliabilityRecords: $_" | Out-File $out -Append
}

"`n--- EVENTOS DE ERRO/CRITICO NO SISTEMA (últimas 24h) ---" | Out-File $out -Append
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-1)} -ErrorAction Stop |
        Select-Object TimeCreated, Id, ProviderName, Message |
        Format-Table -Wrap | Out-File $out -Append
} catch {
    "Sem eventos críticos nas últimas 24h ou log inacessível: $_" | Out-File $out -Append
}

"`n--- ENERGIA / THROTTLING TÉRMICO ---" | Out-File $out -Append
try {
    powercfg /batteryreport /output "battery_report.html" | Out-Null
    "Relatório de bateria gerado em battery_report.html" | Out-File $out -Append
} catch {
    "Não foi possível gerar battery report: $_" | Out-File $out -Append
}
Get-CimInstance -Namespace root\WMI -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction SilentlyContinue |
    Select-Object Name, PercentProcessorPerformance, PercentProcessorTime |
    Format-Table | Out-File $out -Append

"`n--- WINDOWS UPDATE PENDENTE ---" | Out-File $out -Append
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $result = $updateSearcher.Search("IsInstalled=0")
    "Updates pendentes: $($result.Updates.Count)" | Out-File $out -Append
    $result.Updates | ForEach-Object { $_.Title } | Out-File $out -Append
} catch {
    "Não foi possível checar Windows Update: $_" | Out-File $out -Append
}

"`n--- FIM ---" | Out-File $out -Append
Write-Host "Concluído. Abra ou envie o conteúdo de: $out"
