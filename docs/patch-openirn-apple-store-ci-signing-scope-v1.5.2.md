# Correctif OpenIRN v1.5.2 — portée de la signature Apple en CI

## Problème corrigé

Les réglages manuels de signature étaient transmis directement à la commande
`xcodebuild archive`. Xcode les appliquait alors à toutes les cibles du graphe,
y compris aux cibles de ressources des plugins Flutter distribués comme Swift
Packages. Ces cibles ne prennent pas en charge les profils de provisioning et
l'archive iOS échouait avec le code 65.

## Correction

- génération, pendant chaque job Apple, d'un fichier XCConfig éphémère ;
- inclusion de ce fichier uniquement dans la configuration de la cible
  applicative `Runner` pour iOS et macOS ;
- conservation de la signature manuelle avec le certificat et le profil déjà
  validés par le workflow ;
- suppression des réglages de signature globaux de la commande d'archive ;
- ajout d'un contrôle empêchant leur réintroduction.

Aucun certificat, profil, mot de passe ou contenu de clé n'est ajouté au dépôt.
Le téléversement App Store Connect et la soumission App Review ne sont pas
effectués par ce patch local.
