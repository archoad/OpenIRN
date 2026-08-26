import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Applies the proxy selected by the current Windows user's Internet settings.
///
/// Dart's [HttpClient] only reads proxy environment variables by default. On
/// Windows, the native runner resolves the PAC/WPAD configuration through
/// WinHTTP for the actual URL of each request.
final class OpenIrnSystemProxy {
  static const MethodChannel _channel = MethodChannel(
    'io.github.archoad.openirn/system_proxy',
  );

  const OpenIrnSystemProxy._();

  static Future<void> configure() async {
    if (!Platform.isWindows) {
      return;
    }

    await _loadWindowsTrustedRoots();
  }

  static Future<HttpClient> createHttpClient(Uri uri) async {
    final client = HttpClient();
    if (!Platform.isWindows) {
      return client;
    }

    try {
      final windowsProxy = await _channel.invokeMethod<String>(
        'resolveProxy',
        <String, String>{'url': uri.toString()},
      );
      if (windowsProxy == null || windowsProxy.trim().isEmpty) {
        return client;
      }

      final proxyConfiguration = toDartProxyConfiguration(
        windowsProxy,
        targetScheme: uri.scheme,
      );
      client.findProxy = (_) => proxyConfiguration;
    } on PlatformException {
      // Preserve Dart's environment-variable proxy fallback when Windows
      // cannot read or evaluate the current user's proxy configuration.
    } on MissingPluginException {
      // Preserve the same fallback for an incomplete Windows runner build.
    }
    return client;
  }

  static Future<void> _loadWindowsTrustedRoots() async {
    try {
      final certificates = await _channel.invokeListMethod<Uint8List>(
        'trustedRoots',
      );
      for (final certificate in certificates ?? const <Uint8List>[]) {
        try {
          SecurityContext.defaultContext.setTrustedCertificatesBytes(
            _pemEncode(certificate),
          );
        } on TlsException {
          // Ignore a malformed store entry while retaining all valid roots.
        }
      }
    } on PlatformException {
      // Dart's built-in trust roots remain active if the Windows store cannot
      // be read. Certificate validation is never disabled.
    } on MissingPluginException {
      // Keep the built-in roots when the native channel is unavailable.
    }
  }

  static List<int> _pemEncode(Uint8List derCertificate) {
    final encoded = base64Encode(derCertificate);
    final pem = StringBuffer('-----BEGIN CERTIFICATE-----\n');
    for (var offset = 0; offset < encoded.length; offset += 64) {
      final end = (offset + 64).clamp(0, encoded.length);
      pem.writeln(encoded.substring(offset, end));
    }
    pem.write('-----END CERTIFICATE-----\n');
    return utf8.encode(pem.toString());
  }

  static String toDartProxyConfiguration(
    String windowsProxy, {
    required String targetScheme,
  }) {
    final rawEntries = windowsProxy
        .split(';')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (rawEntries.isEmpty) {
      return 'DIRECT';
    }

    final schemeEntries = <String, String>{};
    final genericEntries = <String>[];
    for (final entry in rawEntries) {
      final separatorIndex = entry.indexOf('=');
      if (separatorIndex > 0) {
        final scheme = entry.substring(0, separatorIndex).trim().toLowerCase();
        final proxy = entry.substring(separatorIndex + 1).trim();
        if (scheme.isNotEmpty && proxy.isNotEmpty) {
          schemeEntries[scheme] = proxy;
        }
      } else {
        genericEntries.add(entry);
      }
    }

    final selectedEntries = schemeEntries.isEmpty
        ? genericEntries
        : <String>[
            ?schemeEntries[targetScheme.toLowerCase()],
            ...genericEntries,
          ];
    if (selectedEntries.isEmpty) {
      return 'DIRECT';
    }

    final dartEntries = selectedEntries
        .map(_normalizeProxyEndpoint)
        .where((entry) => entry.isNotEmpty)
        .map(
          (entry) =>
              entry.toUpperCase() == 'DIRECT' ? 'DIRECT' : 'PROXY $entry',
        )
        .toList(growable: false);
    return dartEntries.isEmpty ? 'DIRECT' : dartEntries.join('; ');
  }

  static String _normalizeProxyEndpoint(String value) {
    var endpoint = value.trim();
    final upperEndpoint = endpoint.toUpperCase();
    for (final prefix in const <String>['PROXY ', 'HTTP ', 'HTTPS ']) {
      if (upperEndpoint.startsWith(prefix)) {
        endpoint = endpoint.substring(prefix.length).trim();
        break;
      }
    }
    endpoint = endpoint.replaceFirst(
      RegExp(r'^https?://', caseSensitive: false),
      '',
    );
    return endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
  }
}
