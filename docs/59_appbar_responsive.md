# Barres de titre responsives

Les premières versions d'OpenIRN affichaient plusieurs boutons texte dans les barres de titre. Ce comportement était confortable sur macOS, mais provoquait des débordements `RenderFlex overflow` sur iPhone.

La barre de titre standard est désormais :

- flèche de retour automatique à gauche quand la page est empilée dans la navigation ;
- titre de page centré ;
- menu d'actions `⋮` à droite ;
- libellés longs tronqués proprement.

Les actions de page sont définies via `OpenIrnAppBarAction` et affichées dans un `PopupMenuButton`.
