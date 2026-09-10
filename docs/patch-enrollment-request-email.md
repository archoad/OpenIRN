# Demandes d’enrôlement identifiées par email

Ce patch ajoute une adresse email obligatoire lors de l’envoi d’une demande
d’enrôlement. L’adresse est normalisée, validée côté client et côté API, stockée
avec la demande, puis affichée dans **Administration > Terminaux autorisés**.

Après approbation, la fenêtre du code comporte un bouton **Envoyer par email**.
L’API vérifie le tenant, la demande approuvée, l’invitation, l’état et
l’expiration du code avant de l’envoyer à l’adresse enregistrée. Le code reste
stocké uniquement sous forme de HMAC dans MariaDB et n’est pas ajouté aux
journaux d’audit.

Dans **Administration > Terminaux autorisés**, la demande et le terminal sont
désormais rapprochés par leur identifiant physique, avec repli sur l’identifiant
d’enrôlement. Une seule carte est affichée par terminal. Elle distingue
explicitement l’état courant du terminal de celui de la demande et regroupe
l’adresse du demandeur, les dates et les actions disponibles. En présence de
plusieurs demandes historiques, une demande en attente reste prioritaire ; à
défaut, la plus récente est présentée avec le nombre de demandes associées.

La migration MariaDB `172 enrollment_request_email` ajoute la colonne
`device_enrollment_requests.requester_email`. Les lignes antérieures restent
compatibles avec une valeur vide ; toute nouvelle demande doit fournir une
adresse valide.

L’envoi utilise les variables runtime `OPENIRN_SMTP_HOST`,
`OPENIRN_SMTP_PORT`, `OPENIRN_SMTP_SECURITY`, `OPENIRN_SMTP_FROM`,
`OPENIRN_SMTP_USERNAME`, `OPENIRN_SMTP_PASSWORD` et
`OPENIRN_SMTP_TIMEOUT_SECONDS`. Les identifiants sont facultatifs ensemble pour
un relais sans authentification. Aucune valeur réelle ni aucun secret n’est
inclus dans ce patch.

Validations locales réalisées : compilation Python, 83 tests API exécutés
(80 réussis et 3 intégrations MariaDB ignorées faute d’instance locale),
`flutter analyze` sans anomalie, 84 tests Flutter réussis, parité FR/EN/ES/DE
et contrôle du diff.
