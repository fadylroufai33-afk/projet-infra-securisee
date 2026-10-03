# Journal de bord — Infrastructure Windows Server sécurisée et supervisée

> Projet personnel de laboratoire — Master Cybersécurité
> Auteur : Fadyl · Période : 28/09/2026 → 02/10/2026

Ce journal retrace, étape par étape, la construction d'une infrastructure
d'entreprise fictive (**NOVATECH**) entièrement virtualisée, puis son
durcissement, sa supervision et la détection d'attaques. La démarche suit un
fil rouge en quatre temps : **construire → durcir → superviser → détecter**.

---

## 1. Contexte et objectifs

**Objectif pédagogique :** reproduire à petite échelle le système d'information
d'une PME sous Active Directory, puis appliquer une démarche complète de
sécurité défensive (*blue team*), de la configuration initiale jusqu'à la
détection d'incidents.

**Compétences mises en œuvre :**

- Virtualisation et cloisonnement réseau (KVM/libvirt, VLAN logiques, pare-feu)
- Administration Active Directory (annuaire, GPO, délégation, modèle AGDLP)
- Durcissement système conforme aux recommandations (ANSSI / CIS / Microsoft)
- Supervision et détection (SIEM Wazuh, Sysmon, règles MITRE ATT&CK)
- Audit de sécurité et mesure de progression (PingCastle)

---

## 2. Architecture de la maquette

### 2.1 Hôte de virtualisation

| Élément | Valeur |
|---|---|
| Machine | HP Laptop 14-ep0xxx |
| Système | Ubuntu Linux |
| Processeur | Intel 13ᵉ génération (10 cœurs / 12 threads) |
| Mémoire | 16 Go |
| Stockage | NVMe 468 Go |
| Hyperviseur | KVM / libvirt / virt-manager |

### 2.2 Réseaux (cloisonnement)

Quatre réseaux logiques isolés, séparés par le pare-feu OPNsense :

| Réseau | Interface | Plage | Rôle |
|---|---|---|---|
| WAN | (NAT libvirt) | 192.168.122.0/24 | Accès Internet |
| SERVEURS | virbr10 | 10.10.10.0/24 | Contrôleur de domaine, serveur de fichiers |
| CLIENTS | virbr20 | 10.10.20.0/24 | Postes de travail utilisateurs |
| ADMIN | virbr30 | 10.10.30.0/24 | Supervision (Wazuh), administration |

### 2.3 Machines virtuelles

| VM | Système | RAM | IP | Rôle |
|---|---|---|---|---|
| **FW01-OPNsense** | OPNsense 26.7 | 1 Go | 10.10.10.254 / .20.254 / .30.254 | Pare-feu / routeur inter-réseaux |
| **DC01** | Windows Server 2022 | 3 Go | 10.10.10.10 | Contrôleur de domaine, DNS, DHCP |
| **SRV-FILES** | Windows Server 2022 | 3 Go | 10.10.10.20 | Serveur de fichiers (partages) |
| **PC-W11-01** | Windows 11 Entreprise | 3 Go | 10.10.20.100 (DHCP) | Poste client du domaine |
| **SRV-WAZUH** | Ubuntu Server 24.04 | 4 Go | 10.10.30.10 | SIEM (supervision & détection) |

> **Domaine Active Directory :** `ad.novatech.lan` (NetBIOS : NOVATECH)

---

## 3. Phase 0 — Socle : virtualisation et réseau

**Dates : 28/09**

- Vérification des capacités matérielles de l'hôte (virtualisation activée,
  RAM, espace disque).
- Installation de la pile KVM / libvirt / virt-manager.
- Création des quatre réseaux virtuels isolés (`default`, `lab-servers`,
  `lab-clients`, `lab-admin`).
- Déploiement de la VM **FW01-OPNsense** et configuration des interfaces
  (WAN en DHCP, trois interfaces internes : SERVEURS, CLIENTS, ADMIN).

**Résultat :** une base réseau cloisonnée, où aucun réseau ne communique avec
un autre sans passer par le pare-feu.

*Captures associées : 01 à ~10 (création des réseaux, installation et
configuration d'OPNsense).*

---

## 4. Phase 1 — Infrastructure Windows

**Dates : 28/09 → 29/09**

### 4.1 Contrôleur de domaine (DC01)

- Installation de Windows Server 2022 (expérience de bureau).
- Promotion en contrôleur de domaine : création de la forêt `ad.novatech.lan`.
- Configuration des rôles **DNS** (avec redirecteur vers le pare-feu) et
  **DHCP** (étendue pour le réseau CLIENTS, relais DHCP via OPNsense).

### 4.2 Structure de l'annuaire (script `01-Structure-AD.ps1`)

- Arborescence d'**unités d'organisation (OU)** calquée sur une organisation
  réelle : Administration (Tier 0/1/2), Utilisateurs (par service), Ordinateurs
  (postes fixes / portables), Serveurs, Groupes, Comptes de service.
- Création de **11 utilisateurs** répartis dans 5 services.
- Groupes globaux par service (`GG_*`).
- Redirection des nouveaux comptes d'ordinateurs vers l'OU dédiée (`redircmp`).

### 4.3 Gestion des droits — modèle AGDLP (script `02-Groupes-AGDLP.ps1`)

Application du modèle **AGDLP** (Account → Global → Domain Local → Permission),
la bonne pratique Microsoft pour gérer les accès aux ressources :
groupes de domaine local `DL_Partage_*_RW` / `_RO`.

### 4.4 Serveur de fichiers (SRV-FILES, script `03-Partages.ps1`)

- Disque dédié aux données (S:).
- Création des partages avec permissions NTFS héritées du modèle AGDLP.
- Activation de l'**énumération basée sur l'accès (ABE)** et du **chiffrement
  SMB3**.

### 4.5 Poste client (PC-W11-01)

- Windows 11 Entreprise avec TPM et Secure Boot.
- Jonction au domaine NOVATECH, obtention d'une adresse par DHCP.
- Ouverture de session avec un compte utilisateur du domaine (test de bout
  en bout de l'annuaire).

*Captures associées : ~11 à ~25 (installation DC, structure AD, DHCP, jonction
au domaine, partages, connexion client).*

---

## 5. Phase 2 — Durcissement et audit

**Dates : 30/09 → 01/10**

### 5.1 Durcissement Active Directory (script `04-Durcissement-AD.ps1`)

- `MachineAccountQuota` ramené à 0 (empêche un utilisateur standard de joindre
  des machines au domaine).
- Compte Administrateur marqué « sensible et non délégable ».
- Groupe **Schema Admins** vidé (principe du moindre privilège, accès
  juste-à-temps).
- Activation de la **corbeille Active Directory**.
- Protection des OU contre la suppression accidentelle.
- **Politique de mots de passe** renforcée : 14 caractères minimum, historique
  de 24, verrouillage après 5 essais pendant 15 minutes.

### 5.2 Stratégies de groupe de sécurité (script `05-GPO-Securite.ps1`)

- **GPO « SEC - Domaine - Durcissement réseau »** : NTLMv2 imposé (niveau 5),
  LLMNR désactivé, journalisation PowerShell, chemins UNC renforcés
  (SYSVOL / NETLOGON).
- **GPO « SEC - DC - Audit avancé »** : politique d'audit détaillée
  (connexions, Kerberos, modifications d'annuaire…), conforme aux
  recommandations de référence.

### 5.3 Mots de passe administrateurs locaux — LAPS (script `06-LAPS.ps1`)

- Déploiement de **Windows LAPS** : mot de passe administrateur local unique
  par machine, renouvelé tous les 30 jours, stocké **chiffré dans l'annuaire**.

### 5.4 Mises à jour

- Application des mises à jour Windows sur les serveurs via `sconfig`.

### 5.5 Audit avec PingCastle

Mesure objective de la posture de sécurité du domaine avec **PingCastle**,
avant / après durcissement :

| Étape | Score de risque (/100) |
|---|---|
| État initial | **45** |
| Après premières corrections | 35 |
| Après GPO & délégation | 25 |
| Après LAPS & audit | 10 |
| **État final** | **5** |

> Un score plus bas = un domaine plus sûr. Passage de **45 à 5/100**.
> Le point restant (`NotEnoughDC` — un seul contrôleur de domaine) est un
> **risque accepté et documenté**, inhérent à une maquette de laboratoire.

*Captures associées : ~26 à ~40 (GPO, LAPS, mises à jour, scores PingCastle
successifs).*

---

## 6. Phase 3 — Supervision et détection

**Dates : 01/10 → 02/10**

### 6.1 SIEM Wazuh (SRV-WAZUH)

- Installation de **Wazuh 4.14** (serveur all-in-one) sur un Ubuntu Server
  placé dans le **réseau d'administration isolé** (10.10.30.0/24).
- Configuration réseau statique définitive, extension du volume de stockage.

### 6.2 Agents et journalisation (script `07-Sysmon-Wazuh.ps1`)

Déploiement sur les **trois machines Windows** (DC01, SRV-FILES, PC-W11-01) :

- Agent Wazuh raccordé au manager (10.10.30.10).
- **Sysmon** avec la configuration de référence SwiftOnSecurity.
- Collecte centralisée des journaux **Sysmon** et **PowerShell/Operational**.

> Le pare-feu n'autorise les postes qu'à joindre les ports de collecte Wazuh
> (1514/1515) : le tableau de bord d'administration (443) reste inaccessible
> depuis le réseau CLIENTS — cloisonnement volontaire.

### 6.3 Évaluation de configuration (SCA)

Le module **Security Configuration Assessment** de Wazuh évalue DC01 contre le
référentiel **CIS Microsoft Windows Server 2022 Benchmark** : score de départ
**27 %** (98 contrôles réussis / 261 échoués) — base de travail identifiée pour
un futur alignement.

### 6.4 Règles de détection personnalisées (`local_rules.xml`)

Au-delà des règles par défaut, écriture de **règles de détection maison**,
cartographiées sur **MITRE ATT&CK** :

| Règle | Description | Technique MITRE |
|---|---|---|
| 100100 | Échec de pré-authentification Kerberos (mauvais mot de passe) | T1110 |
| 100101 | Anomalie d'authentification sur plusieurs comptes depuis une même source | T1110.003 |
| 100102 | Même anomalie via ouverture de session (NTLM/SMB) | T1110.003 |
| 100110 | Demande de ticket de service Kerberos en chiffrement faible RC4 | T1558.003 (Kerberoasting) |

Validation de la syntaxe (`wazuh-analysisd -t`) puis rechargement du manager.

### 6.5 Validation de la détection (bout en bout)

- Une **authentification échouée réelle** sur le domaine a déclenché la règle
  personnalisée **100100**, visible sur le tableau de bord avec l'IP source,
  le compte visé et la technique MITRE T1110.
- Chaîne complète vérifiée : **événement → agent → analyse → alerte**.

*Captures associées : ~41 à 50 (installation Wazuh, 3 agents, Sysmon, SCA,
règles de détection, alerte sur le tableau de bord).*

---

## 7. Bilan et perspectives

### Résultats

- Infrastructure d'entreprise complète, cloisonnée et fonctionnelle.
- Posture de sécurité du domaine : **PingCastle 45 → 5/100**.
- Supervision centralisée sur les 3 machines Windows.
- Détection d'attaques Active Directory validée de bout en bout.

### Perspectives d'évolution

- Démonstration offensive contrôlée (Atomic Red Team) pour éprouver les règles.
- Alignement sur le benchmark CIS (SCA : 27 % → objectif supérieur).
- Second contrôleur de domaine (lève le point `NotEnoughDC`), PKI interne,
  WSUS, sauvegardes, compte dédié à la jonction au domaine.

---

## Annexe — Légende des captures d'écran

| N° | Description |
|---|---|
| 01–05 | Vérification matérielle, installation KVM, création des réseaux virtuels |
| 06–10 | Installation et configuration d'OPNsense (interfaces, règles) |
| 11–15 | Installation de Windows Server 2022, promotion DC01 |
| 16–20 | Structure Active Directory (OU, utilisateurs, groupes) |
| 21–25 | DNS, DHCP, jonction du poste client au domaine |
| 26–30 | Serveur de fichiers, partages AGDLP |
| 31–35 | GPO de durcissement, LAPS, audit avancé |
| 36–40 | Scores PingCastle successifs (45 → 5) |
| 41–45 | Installation Wazuh, déploiement des agents, Sysmon |
| 46–50 | Règles de détection, test, alerte sur le tableau de bord |

*(14V : variante de la capture 14.)*
