# Diagnostic OpenIRN — bouton Tester la connexion API

Si `curl https://www.archoad.io/api/health` répond en `HTTP 200`, mais que le bouton `Tester` d’OpenIRN ne produit aucune requête dans les logs serveur, le problème est côté client.

Le cas le plus probable sur macOS est l’absence de l’entitlement sandbox :

```xml
<key>com.apple.security.network.client</key>
<true/>
```

Cet entitlement doit être présent dans :

```text
flutter/macos/Runner/DebugProfile.entitlements
flutter/macos/Runner/Release.entitlements
```

OpenIRN a aussi besoin des entitlements de fichiers utilisateur pour l’export/import JSON :

```xml
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

Appliquer :

```bash
chmod +x tools/ensure_openirn_network_permissions.sh
./tools/ensure_openirn_network_permissions.sh
cd flutter
flutter clean
flutter pub get
flutter run -d macos
```

Contrôles utiles :

```bash
grep -R "com.apple.security.network.client" flutter/macos/Runner/*.entitlements
curl -i https://www.archoad.io/api/health
journalctl -u openirn-api -f
```

Si la requête apparaît dans les logs, le bouton doit passer au vert avec `API OpenIRN disponible`.
