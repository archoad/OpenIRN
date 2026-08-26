import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/network/openirn_system_proxy.dart';

void main() {
  group('OpenIrnSystemProxy', () {
    test('conserve une connexion directe décidée par Windows', () {
      expect(
        OpenIrnSystemProxy.toDartProxyConfiguration(
          'DIRECT',
          targetScheme: 'https',
        ),
        'DIRECT',
      );
    });

    test('convertit un proxy PAC en configuration Dart', () {
      expect(
        OpenIrnSystemProxy.toDartProxyConfiguration(
          'proxy.zscaler.example:8080',
          targetScheme: 'https',
        ),
        'PROXY proxy.zscaler.example:8080',
      );
    });

    test('sélectionne le proxy HTTPS d’une configuration Windows', () {
      expect(
        OpenIrnSystemProxy.toDartProxyConfiguration(
          'http=proxy-http.example:8080;https=proxy-tls.example:8443',
          targetScheme: 'https',
        ),
        'PROXY proxy-tls.example:8443',
      );
    });

    test('normalise les préfixes WinHTTP', () {
      expect(
        OpenIrnSystemProxy.toDartProxyConfiguration(
          'PROXY https://proxy.example:443/',
          targetScheme: 'https',
        ),
        'PROXY proxy.example:443',
      );
    });

    test('préserve l’ordre de repli défini par le PAC', () {
      expect(
        OpenIrnSystemProxy.toDartProxyConfiguration(
          'PROXY proxy.example:8080; DIRECT',
          targetScheme: 'https',
        ),
        'PROXY proxy.example:8080; DIRECT',
      );
    });
  });
}
