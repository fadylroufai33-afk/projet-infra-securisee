# =====================================================================
# 02-Groupes-AGDLP.ps1 - Projet NovaTech
# Groupes domaine local (DL) pour les partages, methode AGDLP
# =====================================================================
Import-Module ActiveDirectory

$Racine   = "OU=NOVATECH,$((Get-ADDomain).DistinguishedName)"
$OU_DL    = "OU=Domaine-Local,OU=Groupes,$Racine"
$Services = "Direction","RH","Comptabilite","Informatique","Commercial"

function New-GroupeDL {
    param($Nom, $Description)
    if (-not (Get-ADGroup -Filter "Name -eq '$Nom'")) {
        New-ADGroup -Name $Nom -GroupScope DomainLocal -GroupCategory Security `
            -Path $OU_DL -Description $Description
        Write-Host "[+] Groupe cree : $Nom" -ForegroundColor Green
    }
}

foreach ($s in $Services) {
    New-GroupeDL "DL_Partage_${s}_RW" "Modification sur le partage $s"
    Add-ADGroupMember "DL_Partage_${s}_RW" -Members "GG_$s"

    if ($s -ne "Direction") {
        New-GroupeDL "DL_Partage_${s}_RO" "Lecture seule sur le partage $s"
        Add-ADGroupMember "DL_Partage_${s}_RO" -Members "GG_Direction"
    }
}

New-GroupeDL "DL_Partage_Commun_RW" "Modification sur le partage Commun"
Add-ADGroupMember "DL_Partage_Commun_RW" -Members ($Services | ForEach-Object { "GG_$_" })

Write-Host "`nGroupes DL et leurs membres :" -ForegroundColor Cyan
Get-ADGroup -Filter "Name -like 'DL_Partage_*'" | Sort-Object Name | ForEach-Object {
    "{0,-30} <- {1}" -f $_.Name, ((Get-ADGroupMember $_ | Select-Object -Expand Name) -join ", ")
}