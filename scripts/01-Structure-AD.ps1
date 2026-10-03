<#
    01-Structure-AD.ps1
    --------------------
    Creation de la structure Active Directory du domaine NOVATECH :
      - unites d'organisation (OU) calquees sur l'organisation de l'entreprise
      - groupes globaux par service (modele AGDLP, cote "Global")
      - 11 comptes utilisateurs repartis dans 5 services
      - redirection des nouveaux comptes d'ordinateurs vers une OU dediee

    Domaine : ad.novatech.lan
    A executer sur DC01, dans une console PowerShell en administrateur.
    Prerequis : module ActiveDirectory (RSAT-AD-PowerShell).
#>

Import-Module ActiveDirectory

# --- Variables de base ---------------------------------------------------
$Domaine   = "DC=ad,DC=novatech,DC=lan"
$RacineOU  = "OU=NOVATECH,$Domaine"

# Mot de passe initial des comptes (demande a l'execution, jamais en clair
# dans le script). Les utilisateurs devront le changer a la 1re connexion.
$MotDePasse = Read-Host "Mot de passe initial des comptes utilisateurs" -AsSecureString

# --- 1. Arborescence des unites d'organisation ---------------------------
Write-Host "[*] Creation des unites d'organisation..." -ForegroundColor Cyan

# OU racine de l'entreprise
New-ADOrganizationalUnit -Name "NOVATECH" -Path $Domaine -ProtectedFromAccidentalDeletion $true -ErrorAction SilentlyContinue

# Branches de premier niveau
$BranchesN1 = @("Administration","Utilisateurs","Ordinateurs","Serveurs","Groupes","Comptes-Service")
foreach ($ou in $BranchesN1) {
    New-ADOrganizationalUnit -Name $ou -Path $RacineOU -ProtectedFromAccidentalDeletion $true -ErrorAction SilentlyContinue
}

# Sous-OU : Administration en 3 niveaux (modele Tiering Microsoft)
foreach ($tier in @("Tier0","Tier1","Tier2")) {
    New-ADOrganizationalUnit -Name $tier -Path "OU=Administration,$RacineOU" -ProtectedFromAccidentalDeletion $true -ErrorAction SilentlyContinue
}

# Sous-OU : un service par metier sous Utilisateurs
$Services = @("Direction","RH","Comptabilite","Informatique","Commercial")
foreach ($svc in $Services) {
    New-ADOrganizationalUnit -Name $svc -Path "OU=Utilisateurs,$RacineOU" -ProtectedFromAccidentalDeletion $true -ErrorAction SilentlyContinue
}

# Sous-OU : Ordinateurs (postes fixes / portables)
foreach ($type in @("Postes-Fixes","Portables")) {
    New-ADOrganizationalUnit -Name $type -Path "OU=Ordinateurs,$RacineOU" -ProtectedFromAccidentalDeletion $true -ErrorAction SilentlyContinue
}

# Sous-OU : Groupes (globaux / domaine local, pour le modele AGDLP)
foreach ($g in @("Globaux","Domaine-Local")) {
    New-ADOrganizationalUnit -Name $g -Path "OU=Groupes,$RacineOU" -ProtectedFromAccidentalDeletion $true -ErrorAction SilentlyContinue
}

# --- 2. Groupes globaux par service (A -> G du modele AGDLP) --------------
Write-Host "[*] Creation des groupes globaux..." -ForegroundColor Cyan

$OUGlobaux = "OU=Globaux,OU=Groupes,$RacineOU"
foreach ($svc in $Services) {
    New-ADGroup -Name "GG_$svc" -GroupScope Global -GroupCategory Security `
        -Path $OUGlobaux -Description "Groupe global - service $svc" -ErrorAction SilentlyContinue
}

# --- 3. Comptes utilisateurs ---------------------------------------------
Write-Host "[*] Creation des comptes utilisateurs..." -ForegroundColor Cyan

# Table des utilisateurs : prenom, nom, service, fonction
$Utilisateurs = @(
    @{ Prenom="Claire"; Nom="Martin";   Service="Direction";    Titre="Directrice generale" }
    @{ Prenom="Thomas"; Nom="Bernard";  Service="Direction";    Titre="Directeur financier" }
    @{ Prenom="Sophie"; Nom="Dubois";   Service="RH";           Titre="Responsable RH" }
    @{ Prenom="Lucas";  Nom="Moreau";   Service="RH";           Titre="Charge de recrutement" }
    @{ Prenom="Julie";  Nom="Laurent";  Service="Comptabilite"; Titre="Comptable" }
    @{ Prenom="Hugo";   Nom="Simon";    Service="Comptabilite"; Titre="Controleur de gestion" }
    @{ Prenom="Nadia";  Nom="Benali";   Service="Informatique"; Titre="Technicienne support" }
    @{ Prenom="Karim";  Nom="Haddad";   Service="Informatique"; Titre="Administrateur systeme" }
    @{ Prenom="Emma";   Nom="Petit";    Service="Commercial";   Titre="Commerciale" }
    @{ Prenom="Leo";    Nom="Garnier";  Service="Commercial";   Titre="Commercial" }
    @{ Prenom="Ines";   Nom="Rousseau"; Service="Commercial";   Titre="Responsable commerciale" }
)

foreach ($u in $Utilisateurs) {
    $login   = "{0}.{1}" -f $u.Prenom.ToLower(), $u.Nom.ToLower()
    $complet = "{0} {1}" -f $u.Prenom, $u.Nom
    $cheminOU = "OU=$($u.Service),OU=Utilisateurs,$RacineOU"

    New-ADUser -Name $complet `
        -GivenName $u.Prenom -Surname $u.Nom `
        -SamAccountName $login `
        -UserPrincipalName "$login@ad.novatech.lan" `
        -Path $cheminOU `
        -Department $u.Service -Title $u.Titre `
        -AccountPassword $MotDePasse `
        -ChangePasswordAtLogon $true `
        -Enabled $true -ErrorAction SilentlyContinue

    # Ajout de l'utilisateur au groupe global de son service
    Add-ADGroupMember -Identity "GG_$($u.Service)" -Members $login -ErrorAction SilentlyContinue
}

# --- 4. Redirection des nouveaux ordinateurs -----------------------------
# Par defaut, un ordinateur joint au domaine atterrit dans CN=Computers.
# On redirige vers notre OU dediee pour qu'il herite des bonnes GPO.
Write-Host "[*] Redirection des nouveaux comptes d'ordinateurs..." -ForegroundColor Cyan
redircmp "OU=Postes-Fixes,OU=Ordinateurs,$RacineOU"

Write-Host "[+] Structure Active Directory creee avec succes." -ForegroundColor Green
