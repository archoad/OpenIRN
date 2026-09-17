# Patch OpenIRN — CI App Store iOS et macOS

Ce patch étend la release GitHub existante sans modifier les circuits Android,
Windows, Microsoft Store ou de génération documentaire.

## Changements

- ajout de deux jobs parallèles après le préflight commun :
  - signature et téléversement iOS dans App Store Connect ;
  - signature et téléversement macOS dans App Store Connect ;
- utilisation du runner GitHub `macos-26` et de l'outil natif `xcodebuild` ;
- import des certificats et profils depuis l'environnement GitHub protégé
  `apple-store` dans un trousseau temporaire ;
- utilisation d'une clé API App Store Connect, sans identifiant Apple ni mot de
  passe spécifique à une application ;
- contrôle de la signature iOS, de la signature macOS, des architectures
  universelles macOS et des permissions du bundle ;
- exclusion des IPA et PKG de la GitHub Release publique ;
- maintien d'une soumission App Review manuelle après traitement des builds par
  Apple ;
- adaptation des contrôles de préflight et de la documentation FR/EN.

## Configuration GitHub attendue

Variables de l'environnement `apple-store` :

- `APP_STORE_CONNECT_KEY_ID` ;
- `APP_STORE_CONNECT_ISSUER_ID` ;
- `APPLE_TEAM_ID`.

Secrets de l'environnement `apple-store` :

- `APP_STORE_CONNECT_PRIVATE_KEY_P8` ;
- `IOS_DISTRIBUTION_P12_BASE64` ;
- `IOS_DISTRIBUTION_P12_PASSWORD` ;
- `IOS_APP_STORE_PROFILE_BASE64` ;
- `MAC_APP_DISTRIBUTION_P12_BASE64` ;
- `MAC_APP_DISTRIBUTION_P12_PASSWORD` ;
- `MAC_INSTALLER_DISTRIBUTION_P12_BASE64` ;
- `MAC_INSTALLER_DISTRIBUTION_P12_PASSWORD` ;
- `MAC_APP_STORE_PROFILE_BASE64`.

## Comportement de publication

Les jobs Apple s'exécutent en parallèle des builds Android, Windows et de la
documentation. La GitHub Release n'est publiée qu'après réussite des deux
téléversements App Store Connect et de la soumission Microsoft Store.

La création du tag, la publication GitHub et la soumission App Review ne sont
pas réalisées par ce patch.
