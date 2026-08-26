---
title: "Déployer les applications OpenIRN"
subtitle: "Android, Windows, macOS, iOS et premier terminal"
author: "Projet OpenIRN"
---

# Lire ceci avant le déploiement

Les releases GitHub OpenIRN publient actuellement des applications signées pour **Android** et **Windows**. La chaîne de release ne publie pas encore d’application macOS ni iOS, faute de chaîne Apple Developer signée et notarizée confirmée.

| Plateforme | Artefact actuellement publié | Déploiement depuis GitHub Release |
|---|---|---|
| Android | `openirn-android.apk`, `openirn-android.aab` | oui |
| Windows x64 | `openirn-windows-x64.msix`, `openirn-windows-signed.zip` | oui |
| macOS | aucun artefact signé/notarizé | non |
| iOS/iPadOS | aucun IPA/TestFlight | non |

Ne renomme pas un binaire non signé en artefact de production. Sur Apple, un build local de développement ne remplace pas une distribution Developer ID, App Store, TestFlight ou MDM correctement signée.

> Les clients officiels actuels utilisent l’API fixe `https://www.archoad.io/api`. Pour une autre URL serveur, il faut produire un client spécifique après modification de `SyncConfiguration.fixedApiBaseUrl`; les binaires génériques de la release ne permettent pas de saisir librement une URL.

# 1. Choisir et vérifier une release

Ouvre la page **Releases** du dépôt `archoad/OpenIRN` et sélectionne une version publiée, non un artefact provenant d’une branche ou d’une exécution inconnue.

Télécharge aussi `SHA256SUMS.txt`. Vérifie que le tag de la release correspond à la version attendue par ton plan de déploiement.

## Vérification sous macOS ou Linux

Place les fichiers dans le même répertoire :

```bash
cd ~/Downloads/OpenIRN-release
shasum -a 256 -c SHA256SUMS.txt
```

Sous Linux, `sha256sum -c SHA256SUMS.txt` produit le même contrôle.

Chaque artefact téléchargé doit être marqué `OK`. Un échec impose de supprimer le fichier et de le télécharger de nouveau depuis la release officielle.

## Vérification sous Windows PowerShell

```powershell
Set-Location "$HOME\Downloads\OpenIRN-release"
Get-Content .\SHA256SUMS.txt
Get-FileHash .\openirn-windows-x64.msix -Algorithm SHA256
Get-FileHash .\openirn-windows-signed.zip -Algorithm SHA256
```

Compare les empreintes sans ignorer un caractère. Pour le MSIX, vérifie aussi la signature :

```powershell
Get-AuthenticodeSignature .\openirn-windows-x64.msix |
  Format-List Status,StatusMessage,SignerCertificate,TimeStamperCertificate
```

Le statut doit être `Valid` et l’éditeur attendu doit être Archoad.

# 2. Déployer sur Android

Deux formats sont publiés :

- l’APK sert au déploiement direct ou via une solution MDM ;
- l’AAB sert à publier dans Google Play et ne s’installe pas directement sur un terminal.

## Installation manuelle de l’APK

1. Télécharge `openirn-android.apk` depuis la release.
2. Vérifie son empreinte SHA-256.
3. Transfère le fichier sur le terminal par un canal maîtrisé.
4. Autorise temporairement l’installation d’applications inconnues pour l’application qui ouvre l’APK.
5. Ouvre l’APK et confirme l’installation.
6. Retire l’autorisation « sources inconnues » après l’installation.

Ne désinstalle pas la version précédente pour une mise à jour normale : une désinstallation supprime la configuration locale et le secret d’enrôlement conservé dans le stockage sécurisé.

## Installation contrôlée avec ADB

Après activation temporaire du débogage USB :

```bash
adb devices
adb install -r openirn-android.apk
```

Résultat attendu : `Success`. Désactive ensuite le débogage USB si le poste n’en a plus besoin.

Pour identifier la version installée :

```bash
adb shell dumpsys package io.github.archoad.openirn | grep -E 'versionName|versionCode'
```

## Déploiement via MDM ou EMM

Importe l’APK signé dans le catalogue privé de l’organisation, ou publie l’AAB dans une piste Google Play gérée. Affecte d’abord l’application à un groupe pilote. Conserve le même identifiant Android `io.github.archoad.openirn` pour permettre la mise à jour en place.

# 3. Déployer sur Windows x64

Le MSIX est le format recommandé pour un parc administré. Le ZIP portable sert à un test maîtrisé ou à un environnement qui ne déploie pas encore de MSIX.

## Option recommandée : MSIX signé

1. Télécharge `openirn-windows-x64.msix`.
2. Vérifie SHA-256 et la signature Authenticode.
3. Double-clique sur le MSIX.
4. Vérifie que Windows affiche l’éditeur Archoad.
5. Clique sur **Installer**.
6. Lance OpenIRN depuis le menu Démarrer.

En PowerShell, une installation interactive peut aussi être lancée ainsi :

```powershell
Add-AppxPackage -Path .\openirn-windows-x64.msix
```

Contrôle le package installé :

```powershell
Get-AppxPackage -Name Archoad.OpenIRN |
  Select-Object Name,PackageFullName,Version,Publisher
```

Une mise à jour MSIX doit utiliser la même identité et un numéro de version supérieur. Teste d’abord la mise à jour sur un terminal pilote déjà enrôlé.

## Option portable : ZIP signé

```powershell
New-Item -ItemType Directory -Force "$HOME\Applications\OpenIRN" | Out-Null
Expand-Archive .\openirn-windows-signed.zip \
  -DestinationPath "$HOME\Applications\OpenIRN" \
  -Force
Get-AuthenticodeSignature "$HOME\Applications\OpenIRN\OpenIRN.exe" |
  Format-List Status,SignerCertificate,TimeStamperCertificate
& "$HOME\Applications\OpenIRN\OpenIRN.exe"
```

Ne déplace pas uniquement `OpenIRN.exe` : le ZIP contient les bibliothèques nécessaires à côté de l’exécutable.

# 4. Déployer sur macOS

## État actuel

La release GitHub ne contient pas de `.dmg`, `.pkg` ni `.app` signé et notarizé. Il n’existe donc pas aujourd’hui de recette de déploiement macOS **à partir de la release GitHub**.

Le blocage n’est pas fonctionnel : il concerne la signature Apple et les droits Keychain utilisés pour le stockage sécurisé du jeton terminal. La validation locale connue d’un build macOS s’est arrêtée sur l’absence du certificat de développement exigé par les entitlements.

## Critères avant ouverture du déploiement macOS

La release devra fournir un artefact :

- signé avec une identité Developer ID Application valide ;
- notarizé par Apple ;
- agrafé lorsque le format le permet ;
- contenant les entitlements Keychain attendus ;
- accompagné de son empreinte SHA-256.

Les contrôles opérateur seront alors :

```bash
shasum -a 256 OpenIRN-macos.dmg
spctl --assess --type open --verbose=4 OpenIRN-macos.dmg
codesign --verify --deep --strict --verbose=2 /Applications/OpenIRN.app
spctl --assess --type execute --verbose=4 /Applications/OpenIRN.app
```

N’utilise pas `xattr -dr com.apple.quarantine` comme procédure standard : cette commande contourne un contrôle de sécurité au lieu de valider la provenance.

# 5. Déployer sur iOS ou iPadOS

## État actuel

La release GitHub ne fournit ni IPA signé ni lien TestFlight. Un iPhone ou iPad non géré ne peut donc pas recevoir OpenIRN depuis la release actuelle.

## Canaux acceptables pour le futur PoC

- **TestFlight** pour un groupe de testeurs identifié ;
- **Apple Business Manager + MDM** pour un parc géré ;
- **distribution Ad Hoc** seulement pour une liste limitée d’UDID enregistrés ;
- App Store lorsque le projet adoptera ce canal.

Le paquet devra conserver le bundle ID `io.github.archoad.openirn`, les entitlements Keychain et une signature issue de l’équipe Apple autorisée. La réussite de `flutter build ios --no-codesign` ne suffit pas à prouver qu’un IPA distribuable existe.

# 6. Préparer le serveur avant le premier lancement

Le serveur doit déjà répondre :

```bash
curl --fail --silent --show-error https://www.archoad.io/api/health
```

Pour une instance neuve, crée le premier administrateur solution sur le serveur :

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	.venv/bin/python tools/create_superuser.py \
		--tenant "$OPENIRN_SOLUTION_ADMIN_TENANT_ID" \
		--tenant-name 'Administration OpenIRN' \
		--first-name 'Prénom' \
		--last-name 'Nom' \
		--email 'admin@example.org'
)
```

Le PIN temporaire est saisi interactivement et devra être changé lors de la première connexion.

Recharge l’API pour réconcilier le profil administrateur solution avec les espaces déjà présents :

```bash
systemctl restart openirn-api
systemctl is-active openirn-api
```

Crée ensuite un code pour le premier terminal :

```bash
cd /opt/openirn-api
(
	set -a
	. /etc/openirn-api.env
	set +a
	.venv/bin/python tools/create_bootstrap_enrollment.py \
		--tenant "$OPENIRN_SOLUTION_ADMIN_TENANT_ID" \
		--label 'Premier terminal OpenIRN' \
		--expires 10
)
```

Le code est secret, temporaire et à usage unique.

# 7. Initialiser la première application

Sur le terminal fraîchement installé :

1. Ouvre OpenIRN.
2. Choisis l’espace de travail d’administration.
3. Sélectionne **Autoriser ce terminal**.
4. Saisis le code bootstrap fourni par l’administrateur serveur.
5. Vérifie que l’accueil indique que le terminal est autorisé.
6. Sélectionne **Déverrouiller OpenIRN**.
7. Choisis le compte administrateur solution.
8. Saisis le PIN temporaire.
9. Lorsque l’application l’exige, choisis un nouveau PIN non trivial.

Le jeton terminal est enregistré dans le stockage sécurisé de la plateforme. La session utilisateur, elle, reste uniquement en mémoire et disparaît à la fermeture ou au verrouillage.

# 8. Ajouter les terminaux suivants

Deux méthodes existent.

## Demande depuis le nouveau terminal

1. Sur le nouveau terminal, choisis l’espace.
2. Ouvre **Autoriser ce terminal**.
3. Sélectionne **Demander une autorisation**.
4. Sur un terminal administrateur ou Pilote IRN déjà autorisé, ouvre **Administration → Terminaux autorisés**.
5. Vérifie le nom, la plateforme et l’espace demandés.
6. Approuve ou refuse la demande.
7. Transmets le code à usage unique au détenteur du nouveau terminal par un canal distinct.
8. Sur le nouveau terminal, saisis le code et termine l’enrôlement.

## Code créé par l’administration

Depuis **Administration → Terminaux autorisés**, crée un code pour l’espace concerné, puis fais-le consommer par le nouveau terminal. L’autorisation reste limitée à cet espace : un même appareil doit être explicitement enrôlé dans chaque espace nécessaire.

# 9. Recette après déploiement

Sur chaque plateforme :

1. Vérifie la version dans **À propos / Licence**.
2. Vérifie la langue et l’affichage.
3. Choisis le bon espace de travail.
4. Contrôle l’état d’autorisation du terminal.
5. Ouvre puis verrouille une session utilisateur.
6. Consulte le référentiel officiel.
7. Ouvre une campagne de test en lecture.
8. Vérifie le retour à l’accueil après fermeture et relance.

Pour un rôle habilité, ajoute un test d’écriture non destructif sur une campagne de recette, puis vérifie la synchronisation sur un second terminal.

# 10. Mettre à jour les applications

Avant une vague de mise à jour :

1. vérifie la release et ses empreintes ;
2. confirme la compatibilité annoncée avec la version d’API ;
3. sauvegarde le serveur ;
4. déploie sur un petit groupe pilote ;
5. vérifie que le terminal reste enrôlé ;
6. vérifie ouverture de session, lecture, écriture et synchronisation ;
7. élargis progressivement le déploiement.

Sur Android, utilise `adb install -r` ou la mise à jour MDM sans désinstallation. Sur Windows, installe le MSIX de version supérieure avec la même identité. Une révocation de terminal n’est pas une désinstallation : elle coupe l’accès serveur de cet appareil pour l’espace concerné.

# 11. Retirer un terminal

1. Dans **Administration → Terminaux autorisés**, sélectionne l’espace.
2. Identifie le terminal par son nom, sa plateforme et sa dernière activité.
3. Révoque son autorisation.
4. Vérifie dans le journal sécurité que la révocation est enregistrée.
5. Désinstalle ensuite l’application ou efface le poste selon la politique du parc.

La révocation serveur est prioritaire : une simple désinstallation ne révoque pas automatiquement l’autorisation persistante.
