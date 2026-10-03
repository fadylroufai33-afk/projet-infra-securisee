# =====================================================================
# 03-Partages.ps1 - Projet NovaTech
# Dossiers, permissions NTFS (AGDLP) et partages SMB securises
# =====================================================================
$Racine   = "S:\Partages"
$Partages = "Direction","RH","Comptabilite","Informatique","Commercial","Commun"

# Noms des groupes integres, quelle que soit la langue de Windows
function Get-NomDepuisSID($sid) {
    (New-Object System.Security.Principal.SecurityIdentifier $sid).Translate(
        [System.Security.Principal.NTAccount]).Value
}
$Admins    = Get-NomDepuisSID "S-1-5-32-544"   # Administrateurs
$AuthUsers = Get-NomDepuisSID "S-1-5-11"       # Utilisateurs authentifies

# Dossier racine : pas d'heritage, les utilisateurs peuvent seulement le traverser
New-Item -ItemType Directory -Path $Racine -Force | Out-Null
icacls $Racine /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-11:(RX)" | Out-Null

foreach ($p in $Partages) {
    $chemin = "$Racine\$p"
    New-Item -ItemType Directory -Path $chemin -Force | Out-Null

    # NTFS : admins et SYSTEM en controle total, groupe RW en modification
    icacls $chemin /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" `
        "NOVATECH\DL_Partage_${p}_RW:(OI)(CI)M" | Out-Null

    # Groupe RO en lecture, s'il existe pour ce partage
    if ($p -notin "Direction","Commun") {
        icacls $chemin /grant "NOVATECH\DL_Partage_${p}_RO:(OI)(CI)RX" | Out-Null
    }

    # Partage SMB : droits larges au niveau du partage, c'est le NTFS qui filtre.
    # Enumeration basee sur l'acces + chiffrement SMB 3
    if (-not (Get-SmbShare -Name $p -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $p -Path $chemin -FullAccess $Admins -ChangeAccess $AuthUsers `
            -FolderEnumerationMode AccessBased -EncryptData $true | Out-Null
        Write-Host "[+] Partage cree : \\SRV-FILES\$p" -ForegroundColor Green
    }
}

# SMBv1 desactive (WannaCry, EternalBlue)
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force

Write-Host "`nPartages :" -ForegroundColor Cyan
Get-SmbShare | Where-Object Path -like "$Racine*" |
    Format-Table Name, Path, FolderEnumerationMode, EncryptData -AutoSize