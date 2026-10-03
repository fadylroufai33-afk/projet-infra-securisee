# =====================================================================
# 07-Sysmon-Wazuh.ps1 - Projet NovaTech
# Installe Sysmon (config SwiftOnSecurity) et envoie ses journaux,
# ainsi que ceux de PowerShell, a l'agent Wazuh
# A executer sur chaque machine Windows supervisee
# =====================================================================
$Dossier = "C:\Outils\Sysmon"
New-Item -ItemType Directory -Path $Dossier -Force | Out-Null
Set-Location $Dossier
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- 1. Sysmon ---
if (-not (Get-Service Sysmon64 -ErrorAction SilentlyContinue)) {
    Invoke-WebRequest "https://download.sysinternals.com/files/Sysmon.zip" -OutFile Sysmon.zip
    Expand-Archive Sysmon.zip -DestinationPath . -Force
    Invoke-WebRequest "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml" -OutFile sysmonconfig.xml
    .\Sysmon64.exe -accepteula -i sysmonconfig.xml | Out-Null
    Write-Host "[+] Sysmon installe avec la configuration SwiftOnSecurity" -ForegroundColor Green
}

# --- 2. Collecte par l'agent Wazuh ---
$Conf = "C:\Program Files (x86)\ossec-agent\ossec.conf"
$Contenu = [IO.File]::ReadAllText($Conf)
if ($Contenu -notmatch "Sysmon/Operational") {
    $Ajout = @"
  <localfile>
    <location>Microsoft-Windows-Sysmon/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>
  <localfile>
    <location>Microsoft-Windows-PowerShell/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

"@
    $Position = $Contenu.LastIndexOf("</ossec_config>")
    [IO.File]::WriteAllText($Conf, $Contenu.Insert($Position, $Ajout))
    Write-Host "[+] Journaux Sysmon et PowerShell ajoutes a l'agent Wazuh" -ForegroundColor Green
}

Get-Service Wazuh* | Restart-Service
Get-Service Sysmon64, Wazuh* | Format-Table Name, Status -AutoSize