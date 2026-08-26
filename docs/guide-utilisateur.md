---
title: "Guide utilisateur OpenIRN"
subtitle: "Conduire une évaluation de l’Indice de Résilience Numérique"
author: "Projet OpenIRN"
---

# Bienvenue dans OpenIRN

OpenIRN aide une organisation à structurer et conduire des évaluations de l’Indice de Résilience Numérique. L’application permet de préparer le périmètre, répartir les critères entre plusieurs personnes, saisir et justifier les réponses, contrôler la qualité et produire une synthèse.

OpenIRN est un outil de travail indépendant. Il ne délivre pas une certification et ne remplace pas l’interprétation du référentiel officiel publié par l’aDRI / Digital Resilience Initiative.

# 1. Comprendre les mots utilisés

| Mot | Signification dans OpenIRN |
|---|---|
| Espace de travail | périmètre isolé d’une organisation ou d’une équipe |
| Fonction critique | activité métier que l’organisation doit préserver |
| Système d’information, ou SI | ensemble de moyens qui soutient une fonction critique |
| Actif | composant humain, informationnel, logiciel, matériel ou fournisseur du SI |
| Campagne | évaluation IRN d’un SI et de ses actifs |
| Critère | question ou attente issue du référentiel IRN |
| Affectation | critère confié à un évaluateur |
| Justification | élément factuel expliquant la réponse choisie |
| Synthèse | vue consolidée des résultats de la campagne |
| Terminal | ordinateur, téléphone ou tablette qui utilise OpenIRN |

# 2. Les rôles, leurs droits et leur mission

Chaque personne possède un rôle dans son espace de travail. Un compte inactif n’a aucun droit, quel que soit son rôle affiché.

## Administrateur

**Mission :** garantir le fonctionnement, la sécurité et la bonne configuration d’OpenIRN.

L’administrateur peut :

- consulter le référentiel et toutes les campagnes ;
- créer, modifier, supprimer et réinitialiser des campagnes ;
- répondre à tous les critères et modifier les informations de campagne ;
- gérer les affectations, exports et journaux de campagne ;
- gérer l’inventaire des fonctions critiques, SI et actifs ;
- gérer les utilisateurs et leur PIN temporaire ;
- créer et administrer les espaces de travail ;
- approuver, renommer ou révoquer les terminaux ;
- consulter le journal de sécurité et les sessions serveur ;
- mettre à jour le référentiel officiel ;
- consulter les révisions, analyser les conflits et restaurer une révision ;
- contrôler MariaDB et déclencher une sauvegarde.

Un administrateur actif de l’espace désigné comme espace d’administration solution peut administrer les autres espaces. Cette transversalité ne s’applique ni aux pilotes, ni aux évaluateurs, ni aux validateurs, ni aux lecteurs.

## Pilote IRN

**Mission :** organiser l’évaluation et conduire la campagne jusqu’à sa validation.

Le Pilote IRN peut :

- créer et gérer les campagnes de son espace ;
- gérer l’inventaire des fonctions critiques, SI et actifs ;
- créer une campagne à partir d’un SI et de ses actifs ;
- modifier toutes les réponses d’une campagne éditable ;
- affecter des critères aux évaluateurs ;
- consulter la synthèse et le contrôle qualité ;
- faire évoluer le statut de la campagne ;
- exporter les données et consulter le journal d’activité ;
- consulter l’historique et restaurer une révision ;
- gérer les utilisateurs non administrateurs de son espace ;
- traiter les demandes et autorisations de terminaux de son espace.

Le Pilote IRN ne gère pas les espaces, les administrateurs, le journal de sécurité, les sessions serveur, le référentiel officiel ni la maintenance MariaDB.

## Évaluateur

**Mission :** produire des réponses fiables et justifiées sur les critères qui lui sont confiés.

L’évaluateur peut :

- consulter le référentiel ;
- ouvrir les campagnes de son espace ;
- consulter la synthèse et le contrôle qualité ;
- voir les critères qui lui sont affectés ;
- répondre et ajouter des justifications uniquement sur ces critères, tant que la campagne reste éditable.

Il ne crée pas la campagne, ne modifie pas les affectations et ne répond pas aux critères confiés à une autre personne.

## Validateur

**Mission :** relire l’évaluation, apprécier la cohérence des preuves et contribuer au passage en validation.

Le validateur peut :

- consulter le référentiel et les campagnes ;
- consulter les réponses, la synthèse et le contrôle qualité ;
- utiliser le parcours de revue sur une campagne encore éditable.

Il ne réalise pas la saisie courante des critères, ne gère pas les campagnes et n’administre pas la plateforme.

## Lecteur

**Mission :** prendre connaissance des résultats sans les modifier.

Le lecteur peut consulter :

- le référentiel ;
- la liste et le contenu des campagnes ;
- les réponses ;
- la synthèse ;
- le contrôle qualité.

Il ne modifie aucune donnée.

## Matrice résumée

| Fonction | Admin. | Pilote | Évaluateur | Validateur | Lecteur |
|---|:---:|:---:|:---:|:---:|:---:|
| Consulter référentiel et campagnes | oui | oui | oui | oui | oui |
| Consulter synthèse et qualité | oui | oui | oui | oui | oui |
| Répondre à tous les critères | oui | oui | non | non | non |
| Répondre aux critères affectés | oui | oui | oui | non | non |
| Revoir une campagne | oui | oui | non | oui | non |
| Gérer campagnes et affectations | oui | oui | non | non | non |
| Gérer inventaire SI | oui | oui | non | non | non |
| Gérer utilisateurs du même espace | oui | oui, hors administrateurs | non | non | non |
| Gérer terminaux du même espace | oui | oui | non | non | non |
| Gérer espaces et sécurité serveur | oui | non | non | non | non |
| Gérer référentiel et sauvegardes | oui | non | non | non | non |

# 3. Premier démarrage

## Choisir un espace de travail

1. Ouvre OpenIRN.
2. Sélectionne **Choisir un espace de travail**.
3. Choisis l’espace communiqué par ton responsable.
4. Vérifie son nom avant de continuer.

Les données sont isolées par espace. Changer d’espace ne donne aucun droit supplémentaire et peut exiger un nouvel enrôlement du même terminal.

## Autoriser le terminal

Si l’accueil indique que le terminal n’est pas autorisé :

1. Ouvre **Autoriser ce terminal**.
2. Si tu possèdes un code à usage unique, saisis-le.
3. Sinon, sélectionne **Demander une autorisation**.
4. Informe le Pilote IRN ou l’administrateur de l’espace.
5. Lorsque tu reçois un code approuvé, saisis-le avant son expiration.

N’envoie pas le code dans un canal public. Une autorisation concerne un terminal et un espace précis.

## Ouvrir une session

1. Sélectionne **Déverrouiller OpenIRN**.
2. Choisis ton profil.
3. Saisis ton code personnel.
4. Si le code est temporaire, choisis immédiatement un nouveau code.

La session est courte et conservée uniquement en mémoire. OpenIRN se verrouille après une période d’inactivité. Le verrouillage protège la session mais ne révoque pas l’autorisation du terminal.

## Changer de langue

Sélectionne le drapeau affiché dans la barre supérieure, puis choisis la langue. Les langues disponibles dans l’application actuelle sont français, anglais, espagnol et allemand.

# 4. Se repérer dans l’accueil

Après ouverture de session, l’accueil donne accès aux grandes fonctions autorisées :

- **Évaluation Indice de Résilience Numérique** : campagnes et saisie ;
- **Référentiel aDRI IRN** : consultation des piliers et critères ;
- **Administration** : actions réservées aux administrateurs et pilotes ;
- sélection ou changement de l’espace ;
- état de connexion et de synchronisation ;
- changement de langue ;
- **À propos / Licence** : version et informations légales.

Si une carte n’apparaît pas, vérifie d’abord ton rôle. L’interface masque les fonctions interdites et le serveur contrôle également chaque opération sensible.

# 5. Consulter le référentiel officiel

1. Depuis l’accueil, ouvre **Référentiel aDRI IRN**.
2. Consulte les piliers proposés.
3. Ouvre un pilier pour afficher ses critères.
4. Ouvre un critère pour lire son libellé, sa description, son périmètre, ses recommandations et ses références.

La consultation ne modifie aucune campagne. La version active est chargée depuis le serveur ; elle n’est pas une copie métier persistante stockée sur le terminal.

# 6. Préparer l’inventaire SI

Cette fonction est disponible pour l’administrateur et le Pilote IRN dans **Administration → Fonctions critiques, SI & actifs**.

## Créer une fonction critique

1. Sélectionne l’ajout d’une fonction critique.
2. Donne-lui un nom métier compréhensible.
3. Ajoute une description qui explique les conséquences d’une interruption.
4. Enregistre.

## Créer un système d’information

1. Ouvre la fonction critique concernée.
2. Ajoute un système d’information.
3. Indique son nom, sa description et son responsable.
4. Enregistre.

## Ajouter les actifs

Pour chaque actif :

1. sélectionne le SI ;
2. saisis un nom distinctif ;
3. indique le type et une description utile ;
4. attribue une criticité ;
5. enregistre.

Les niveaux de criticité sont :

| Niveau | Libellé | Interprétation pratique |
|---|---|---|
| N1 | standard | impact limité |
| N2 | modérée | impact notable |
| N3 | élevée | impact important |
| N4 | critique | impact majeur pour la fonction |

## Importer ou exporter avec Excel

L’écran permet d’exporter le modèle de l’espace, de le compléter puis de l’importer. Conserve les identifiants protégés du fichier, ne renomme pas arbitrairement les feuilles et examine le rapport de validation avant de confirmer un import.

Un export constitue une copie contenant des informations de cartographie potentiellement sensibles. Stocke-le selon la politique de sécurité de l’organisation.

# 7. Créer une campagne

Cette action appartient à l’administrateur ou au Pilote IRN.

1. Vérifie que le référentiel officiel est installé.
2. Vérifie que le SI et ses actifs existent dans l’inventaire.
3. Ouvre **Administration → Gérer les campagnes**.
4. Choisis la création à partir d’un système d’information.
5. Sélectionne la fonction critique puis le SI.
6. Vérifie la liste des actifs et leur criticité.
7. Saisis le nom, la description et les informations du responsable de projet.
8. Crée la campagne.

La campagne débute au statut **Brouillon**. Évite les noms génériques comme « Test » sur une instance de production.

# 8. Affecter les critères

1. Ouvre la campagne.
2. Ouvre **Affectations des critères**.
3. Choisis un pilier puis un critère.
4. Sélectionne l’évaluateur compétent.
5. Enregistre l’affectation.

Répartis les critères selon la connaissance réelle des actifs, pas seulement selon la disponibilité. Un évaluateur ne peut saisir que ce qui lui est explicitement affecté.

# 9. Répondre à une évaluation

## Choisir l’actif

Lorsqu’une campagne contient plusieurs actifs, sélectionne d’abord l’actif à évaluer. Les réponses sont distinctes par actif.

## Choisir une réponse

OpenIRN utilise les niveaux suivants :

| Réponse | Valeur utilisée | Sens général |
|---|---:|---|
| N.C. | exclue du score | critère non concerné, à justifier |
| Non résilient | 10/100 | absence ou insuffisance forte |
| Intention | 25/100 | volonté identifiée, réalisation limitée |
| Moyen | 50/100 | moyens engagés, résultat encore partiel |
| Résultat | 95/100 | résultat démontré et maîtrisé |

Le choix d’une valeur élevée doit reposer sur des éléments vérifiables. `N.C.` compte dans la complétude mais pas dans le calcul du score.

## Ajouter une justification

Une bonne justification :

- décrit le dispositif réellement en place ;
- cite une preuve, un responsable ou une période ;
- distingue le fait observé du projet futur ;
- reste compréhensible par un relecteur ;
- ne contient pas de mot de passe, token ou secret.

Exemple de structure : « Procédure approuvée le … ; exercice réalisé le … ; compte rendu conservé dans … ; prochaine revue prévue le … ».

## Vérifier l’enregistrement

Observe l’indicateur de synchronisation après une modification. En cas d’erreur, n’effectue pas plusieurs changements contradictoires sur différents terminaux. Note l’heure, conserve le message et préviens le Pilote IRN.

# 10. Utiliser le contrôle qualité

Ouvre **Contrôle qualité** depuis la campagne. L’écran met en évidence notamment :

- les critères sans réponse ;
- les justifications absentes ou à compléter ;
- l’avancement par pilier ou actif ;
- les éléments qui empêchent une revue complète.

Traite les anomalies avant de passer au statut **Prêt pour revue**. Un score ne remplace pas la qualité des preuves.

# 11. Comprendre la synthèse

La synthèse présente les résultats globaux, par pilier et par actif. OpenIRN calcule :

- la note d’un actif à partir d’une moyenne géométrique des scores de ses piliers ;
- la note consolidée d’un SI à partir d’une moyenne géométrique pondérée par la criticité des actifs.

Une valeur très faible peut donc peser fortement sur le résultat. Lis toujours la synthèse avec les réponses et justifications associées.

L’écran peut produire des exports PNG et PDF de synthèse. Vérifie le périmètre, la campagne, l’actif et la date avant diffusion.

# 12. Faire évoluer le statut d’une campagne

| Statut | Usage | Modification |
|---|---|---|
| Brouillon | saisie en cours | autorisée selon le rôle |
| Prêt pour revue | saisie complète, relecture attendue | encore éditable |
| Validé | résultat approuvé | lecture seule |
| Archivé | campagne conservée à titre historique | lecture seule |

Le Pilote IRN, le validateur ou l’administrateur agit selon les commandes proposées par l’interface et ses droits. Avant validation, vérifie le contrôle qualité, le périmètre d’actifs, les justifications et la synthèse.

# 13. Exporter une campagne

Selon les droits disponibles, OpenIRN peut produire :

- un export JSON de campagne ;
- une image PNG de synthèse ;
- un PDF de synthèse ;
- un export JSON du journal d’activité ;
- un fichier Excel d’inventaire.

Les exports peuvent contenir des informations sensibles sur le SI. Avant de les transmettre :

1. ouvre le fichier ;
2. vérifie le nom de la campagne et l’espace ;
3. vérifie qu’aucune information non destinée au destinataire n’y figure ;
4. utilise le canal de partage approuvé par l’organisation.

# 14. Consulter le journal d’activité

Le journal de campagne retrace les événements fonctionnels : modifications, changements de statut, affectations, exports et opérations de synchronisation utiles à l’audit.

Le journal d’activité n’est pas le journal de sécurité. Ce dernier est réservé à l’administrateur et couvre notamment les connexions, échecs d’authentification, enrôlements, révocations et limitations anti-abus.

# 15. Gérer les utilisateurs

L’administrateur et le Pilote IRN ouvrent **Administration → Utilisateurs**.

1. Vérifie l’espace affiché.
2. Ajoute ou modifie le profil.
3. Attribue le rôle strictement nécessaire.
4. Active ou désactive le compte.
5. Enregistre.

Un Pilote IRN ne peut pas créer ou modifier un administrateur. Un nouveau compte ne reçoit pas automatiquement `0000`. Un administrateur attribue un PIN temporaire non trivial ; la personne devra le changer à la première connexion.

Lors d’un départ, désactive le compte et demande à l’administrateur de révoquer ses sessions actives.

# 16. Gérer les terminaux

Dans **Administration → Terminaux autorisés** :

- les demandes en attente apparaissent avant les terminaux ;
- un administrateur voit tous les espaces lorsqu’il dispose du rôle solution ;
- un Pilote IRN ne voit que son espace ;
- l’approbation produit un code temporaire à usage unique ;
- la révocation supprime l’autorisation de cet espace ;
- le renommage facilite l’identification sans changer l’identité technique.

Avant d’approuver, vérifie l’identité du demandeur par un canal distinct. En cas de perte ou de vol, révoque le terminal avant toute autre action.

# 17. Changer ou verrouiller sa session

Pour changer ton code, ouvre **Administration → Changement de code** lorsque cette carte est disponible, saisis le code actuel puis deux fois le nouveau.

Choisis un code non trivial, différent du précédent et non partagé. OpenIRN refuse les suites évidentes et les répétitions.

Verrouille l’application lorsque tu quittes le terminal. Après verrouillage, le terminal reste autorisé mais aucune opération utilisateur sensible n’est permise avant une nouvelle authentification.

# 18. Réagir à un problème courant

| Message ou situation | Action utilisateur |
|---|---|
| Terminal non autorisé | vérifier l’espace puis demander un enrôlement |
| Session expirée | revenir à l’accueil et se déverrouiller de nouveau |
| Aucun critère modifiable | vérifier l’affectation, le rôle et le statut de campagne |
| Campagne en lecture seule | vérifier si elle est Validée ou Archivée |
| Référentiel absent | prévenir un administrateur |
| Synchronisation en erreur | ne pas multiplier les modifications, noter l’heure et le message |
| Code refusé | vérifier qu’il n’est ni expiré, ni déjà consommé, ni saisi dans le mauvais espace |
| Compte absent ou inactif | contacter le Pilote IRN ou l’administrateur |

# 19. Bonnes pratiques pour un PoC élargi

- utilise des comptes nominatifs ;
- attribue le rôle le plus limité compatible avec la mission ;
- nomme clairement espaces, SI, actifs, campagnes et terminaux ;
- demande une justification pour chaque réponse significative ;
- réalise les essais dans une campagne de recette identifiée ;
- ne partage jamais un PIN, un code d’enrôlement ou une capture contenant des secrets ;
- verrouille la session avant de laisser le terminal ;
- signale immédiatement une perte de terminal ;
- exporte uniquement les données nécessaires ;
- fais valider la campagne par une personne différente de l’évaluateur lorsque l’organisation le permet.
