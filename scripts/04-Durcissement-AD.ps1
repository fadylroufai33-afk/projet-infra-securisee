# =====================================================================
# 04-Durcissement-AD.ps1 - Projet NovaTech
# Corrections issues de l'audit PingCastle du 01/10/2026
# =====================================================================
Import-Module ActiveDirectory
$Domaine = Get-ADDomain
$DN      = $Domaine.DistinguishedName
$SID     = $Domaine.DomainSID.Value

function OK($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }

# --- S-ADRegistration : plus aucun utilisateur ne peut joindre de machine ---
Set-ADDomain -Identity $DN -Replace @{"ms-DS-MachineAccountQuota" = 0}
OK "ms-DS-MachineAccountQuota = 0"

# --- S-DC-SubnetMissing : declaration des sous-reseaux dans le site AD ---
$Site = (Get-ADReplicationSite).Name
foreach ($s in "10.10.10.0/24","10.10.20.0/24","10.10.30.0/24") {
    if (-not (Get-ADReplicationSubnet -Filter "Name -eq '$s'")) {
        New-ADReplicationSubnet -Name $s -Site $Site
    }
}
OK "Sous-reseaux declares dans le site $Site"

# --- P-Delegated : compte Administrateur (RID 500) non delegable ---
Set-ADUser -Identity "$SID-500" -AccountNotDelegated $true
OK "Administrateur : 'sensible et non delegable'"

# --- P-SchemaAdmin : groupe Administrateurs du schema vide (RID 518) ---
$SchemaAdmins = Get-ADGroup -Identity "$SID-518"
Get-ADGroupMember $SchemaAdmins | ForEach-Object {
    Remove-ADGroupMember $SchemaAdmins -Members $_ -Confirm:$false
}
OK "Groupe '$($SchemaAdmins.Name)' vide"

# --- P-RecycleBin : corbeille Active Directory ---
$Corbeille = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'"
if (-not $Corbeille.EnabledScopes) {
    Enable-ADOptionalFeature "Recycle Bin Feature" -Scope ForestOrConfigurationSet `
        -Target $Domaine.DNSRoot -Confirm:$false
}
OK "Corbeille AD activee"

# --- P-UnprotectedOU : protection des OU contre la suppression accidentelle ---
Get-ADOrganizationalUnit -Filter * -Properties ProtectedFromAccidentalDeletion |
    Where-Object { -not $_.ProtectedFromAccidentalDeletion } |
    Set-ADOrganizationalUnit -ProtectedFromAccidentalDeletion $true
OK "Toutes les OU protegees"

# --- A-MinPwdLen : politique de mots de passe (recommandations ANSSI) ---
Set-ADDefaultDomainPasswordPolicy -Identity $Domaine.DNSRoot `
    -MinPasswordLength 12 -PasswordHistoryCount 24 -ComplexityEnabled $true `
    -LockoutThreshold 10 -LockoutDuration "00:15:00" -LockoutObservationWindow "00:15:00"
OK "Mots de passe : 12 caracteres min, historique 24, verrouillage apres 10 echecs"

# --- A-PreWin2000AuthenticatedUsers : nettoyage du groupe pre-Windows 2000 ---
try {
    Set-ADGroup -Identity "S-1-5-32-554" `
        -Remove @{member = "CN=S-1-5-11,CN=ForeignSecurityPrincipals,$DN"} -ErrorAction Stop
    OK "'Utilisateurs authentifies' retire du groupe pre-Windows 2000"
} catch { Write-Host "[--] Groupe pre-Windows 2000 : deja propre" -ForegroundColor Yellow }

Write-Host "`nDurcissement AD termine. Relancer PingCastle pour mesurer le gain." -ForegroundColor Cyan