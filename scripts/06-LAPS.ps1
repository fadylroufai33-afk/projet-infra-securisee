# =====================================================================
# 06-LAPS.ps1 - Projet NovaTech
# Deploiement de Windows LAPS sur les postes et les serveurs membres
# Prerequis : schema etendu (Update-LapsADSchema)
# =====================================================================
Import-Module LAPS, ActiveDirectory, GroupPolicy
$Racine = "OU=NOVATECH,$((Get-ADDomain).DistinguishedName)"
$OUs    = "OU=Ordinateurs,$Racine", "OU=Serveurs,$Racine"

# 1. Les ordinateurs peuvent ecrire leur propre mot de passe dans l'AD
foreach ($ou in $OUs) {
    Set-LapsADComputerSelfPermission -Identity $ou | Out-Null
    Write-Host "[OK] Permission d'ecriture LAPS : $ou" -ForegroundColor Green
}

# 2. GPO LAPS liee aux postes et aux serveurs (pas aux DC)
$GPO = "SEC - Postes et serveurs - LAPS"
if (-not (Get-GPO -Name $GPO -ErrorAction SilentlyContinue)) {
    New-GPO -Name $GPO -Comment "Windows LAPS : mot de passe admin local unique" | Out-Null
    foreach ($ou in $OUs) { New-GPLink -Name $GPO -Target $ou | Out-Null }
    Write-Host "[+] GPO creee et liee : $GPO" -ForegroundColor Green
}

# 3. Parametres LAPS
$Cle = "HKLM\Software\Microsoft\Policies\LAPS"
$Parametres = @{
    "BackupDirectory"             = 2    # Sauvegarde dans Active Directory
    "ADPasswordEncryptionEnabled" = 1    # Mot de passe chiffre dans l'AD
    "PasswordComplexity"          = 4    # Majuscules, minuscules, chiffres, symboles
    "PasswordLength"              = 16   # 16 caracteres
    "PasswordAgeDays"             = 30   # Rotation tous les 30 jours
}
foreach ($p in $Parametres.GetEnumerator()) {
    Set-GPRegistryValue -Name $GPO -Key $Cle -ValueName $p.Key -Type DWord -Value $p.Value | Out-Null
}
Write-Host "[OK] Parametres LAPS : AD chiffre, 16 caracteres, complexite max, rotation 30 jours" -ForegroundColor Green