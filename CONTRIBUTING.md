# Contribuer à OpenIRN

Merci de votre intérêt pour OpenIRN.

## Principes du projet

OpenIRN suit quelques principes simples :

- séparer strictement le code applicatif du référentiel IRN officiel ;
- garder le modèle de données auditable ;
- privilégier une architecture frontend-backend ;
- écrire des tests ;
- éviter d’introduire trop tôt des dépendances lourdes.

## Préparer l’environnement

```bash
cd flutter
flutter pub get
flutter test
```

## Avant une pull request

Depuis la racine du dépôt :

```bash
./tools/check_open_source_readiness.sh
cd flutter
flutter analyze
flutter test
```

## Conventions

- Langue des commentaires utilisateur : français.
- Code Dart : noms en anglais lorsque cela améliore la lisibilité technique.
- UI : français pour l’instant.
- Tests : obligatoires pour les services métier.

## Ce qu’il ne faut pas commiter

Ne pas commiter :

- fichiers Excel officiels téléchargés ;
- fichiers Excel d’entreprise ;
- bundles JSON générés du référentiel officiel ;
- exports de campagnes réelles ;
- secrets, tokens, clés API ;
- builds Flutter.
