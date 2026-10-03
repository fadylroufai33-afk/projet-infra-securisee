# =====================================================================
# 05-GPO-Securite.ps1 - Projet NovaTech
# Creation des GPO de securite (parametres registre)
# Les parametres de securite (NTLM, audit) sont regles dans GPMC
# =====================================================================
Import-Module GroupPolicy, ActiveDirectory
$Domaine = Get-ADDomain

function New-GPOSiAbsente($Nom, $Commentaire, $Cible) {
    if (-not (Get-GPO -Name $Nom -ErrorAction SilentlyContinue)) {
        New-GPO -Name $Nom -Comment $Commentaire | Out-Null
        New-GPLink -Name $Nom -Target $Cible | Out-Null
        Write-Host "[+] GPO creee et liee : $Nom -> $Cible" -ForegroundColor Green
    }
}

# --- GPO 1 : durcissement reseau, appliquee a tout le domaine ---
$GPO1 = "SEC - Domaine - Durcissement reseau"
New-GPOSiAbsente $GPO1 "NTLMv2 uniquement, LLMNR desactive, journalisation PowerShell" $Domaine.DistinguishedName

# LLMNR desactive (empoisonnement de noms, outil Responder)
Set-GPRegistryValue -Name $GPO1 -Key "HKLM\Software\Policies\Microsoft\Windows NT\DNSClient" `
    -ValueName "EnableMulticast" -Type DWord -Value 0 | Out-Null

# Journalisation PowerShell (blocs de script + modules), utile pour Wazuh
Set-GPRegistryValue -Name $GPO1 -Key "HKLM\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" `
    -ValueName "EnableScriptBlockLogging" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $GPO1 -Key "HKLM\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging" `
    -ValueName "EnableModuleLogging" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $GPO1 -Key "HKLM\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames" `
    -ValueName "*" -Type String -Value "*" | Out-Null
Write-Host "[OK] LLMNR desactive, journalisation PowerShell activee" -ForegroundColor Green

# --- GPO 2 : audit avance, appliquee aux controleurs de domaine ---
New-GPOSiAbsente "SEC - DC - Audit avance" "Strategie d'audit avancee des DC" $Domaine.DomainControllersContainer

Write-Host "`nA finir dans GPMC : NTLMv2 (GPO 1) et sous-categories d'audit (GPO 2)" -ForegroundColor Cyan