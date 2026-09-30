import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'cloud_config.dart';

/// Name of the folder (or key prefix) boards are kept under in a storage.
const remoteFolderName = 'Local Board';

class RemoteStoreException implements Exception {
  const RemoteStoreException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The three operations sync needs. Names are flat file names.
abstract interface class RemoteStore {
  /// File contents, or null when it does not exist.
  Future<List<int>?> read(String name);
  Future<void> write(String name, List<int> bytes);
  Future<void> delete(String name);
}

RemoteStore remoteStoreFor(CloudStorageConfig config, {HttpClient? client}) => switch (config.provider.kind) {
  CloudKind.folder => FolderRemoteStore(Directory(p.join(config.folder, remoteFolderName))),
  CloudKind.s3 => S3RemoteStore(config, client: client),
  CloudKind.webdav => WebDavRemoteStore(config, client: client),
};

/// Writes a file, reads it back and removes it, so the settings screen can
/// tell the user right away whether a storage works.
Future<void> testRemoteStore(RemoteStore store) async {
  const name = '.local-board-connection-test';
  final payload = utf8.encode('ok ${DateTime.now().toUtc().toIso8601String()}');
  await store.write(name, payload);
  final back = await store.read(name);
  if (back == null || utf8.decode(back) != utf8.decode(payload)) {
    throw const RemoteStoreException('The storage accepted the file but returned something else.');
  }
  await store.delete(name);
}

// ---------------------------------------------------------------------------
// Synced folder (Google Drive, OneDrive, Proton Drive, Dropbox, iCloud…)

final class FolderRemoteStore implements RemoteStore {
  FolderRemoteStore(this.dir);

  final Directory dir;

  File _file(String name) => File(p.join(dir.path, name));

  Future<void> _checkParent() async {
    if (!await dir.parent.exists()) {
      throw RemoteStoreException('Folder not found: ${dir.parent.path}. Is the provider app installed and signed in?');
    }
  }

  @override
  Future<List<int>?> read(String name) async {
    await _checkParent();
    final f = _file(name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// tmp + rename, so the provider app never uploads a half-written file.
  @override
  Future<void> write(String name, List<int> bytes) async {
    await _checkParent();
    await dir.create(recursive: true);
    final tmp = File('${_file(name).path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(_file(name).path);
  }

  @override
  Future<void> delete(String name) async {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }
}

// ---------------------------------------------------------------------------
// HTTP helpers

const _timeout = Duration(seconds: 30);

Future<(int, List<int>)> _send(
  HttpClient client,
  String method,
  Uri uri, {
  Map<String, String> headers = const {},
  List<int>? body,
}) async {
  try {
    final req = await client.openUrl(method, uri).timeout(_timeout);
    headers.forEach(req.headers.set);
    if (body != null) {
      req.contentLength = body.length;
      req.add(body);
    } else if (method == 'PUT' || method == 'MKCOL') {
      req.contentLength = 0;
    }
    final res = await req.close().timeout(_timeout);
    final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(_timeout);
    return (res.statusCode, bytes);
  } on TimeoutException {
    throw RemoteStoreException('No answer from ${uri.host}. Check your connection.');
  } on SocketException catch (e) {
    throw RemoteStoreException('Could not reach ${uri.host}: ${e.osError?.message ?? e.message}');
  } on HandshakeException {
    throw RemoteStoreException('Secure connection to ${uri.host} failed.');
  }
}

String _errorText(int status, List<int> body) {
  final text = utf8.decode(body, allowMalformed: true);
  final code = RegExp(r'<Code>([^<]+)</Code>').firstMatch(text)?.group(1);
  return switch (status) {
    401 || 403 => 'Access denied${code != null ? ' ($code)' : ''}. Check the credentials and permissions.',
    404 => 'Not found${code != null ? ' ($code)' : ''}. Check the address or bucket name.',
    _ => 'The storage answered $status${code != null ? ' ($code)' : ''}.',
  };
}

// ---------------------------------------------------------------------------
// S3 and compatible (AWS, Cloudflare R2, Backblaze B2, Wasabi, MinIO…)

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// RFC 3986 encoding as SigV4 expects (unreserved characters untouched).
String _awsEncode(String s, {bool keepSlash = false}) {
  final out = StringBuffer();
  for (final b in utf8.encode(s)) {
    final c = String.fromCharCode(b);
    if (RegExp(r'[A-Za-z0-9\-._~]').hasMatch(c) || (keepSlash && c == '/')) {
      out.write(c);
    } else {
      out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

/// AWS Signature Version 4 headers for one request (x-amz-date and
/// Authorization). [headers] must include `host`.
Map<String, String> signV4({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  required String payloadHash,
  required String accessKeyId,
  required String secretAccessKey,
  required String region,
  String service = 's3',
  DateTime? now,
}) {
  final t = (now ?? DateTime.now()).toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final date = '${t.year}${two(t.month)}${two(t.day)}';
  final amzDate = '${date}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';

  final all = {for (final e in headers.entries) e.key.toLowerCase(): e.value.trim(), 'x-amz-date': amzDate};
  final names = all.keys.toList()..sort();
  final canonicalHeaders = names.map((n) => '$n:${all[n]}\n').join();
  final signedHeaders = names.join(';');
  final query = uri.queryParametersAll.entries
      .expand((e) => e.value.map((v) => '${_awsEncode(e.key)}=${_awsEncode(v)}'))
      .toList()
    ..sort();
  final canonical = [
    method,
    uri.path.isEmpty ? '/' : uri.path,
    query.join('&'),
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  final scope = '$date/$region/$service/aws4_request';
  final toSign = ['AWS4-HMAC-SHA256', amzDate, scope, _hex(sha256.convert(utf8.encode(canonical)).bytes)].join('\n');
  List<int> hmac(List<int> key, String data) => Hmac(sha256, key).convert(utf8.encode(data)).bytes;
  var key = hmac(utf8.encode('AWS4$secretAccessKey'), date);
  key = hmac(key, region);
  key = hmac(key, service);
  key = hmac(key, 'aws4_request');
  final signature = _hex(hmac(key, toSign));
  return {
    'x-amz-date': amzDate,
    'authorization':
        'AWS4-HMAC-SHA256 Credential=$accessKeyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature',
  };
}

final class S3RemoteStore implements RemoteStore {
  S3RemoteStore(this.config, {HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final CloudStorageConfig config;
  final HttpClient _client;

  /// AWS uses virtual-hosted URLs; custom endpoints use path style, which
  /// every S3-compatible service supports.
  Uri _uri(String name) {
    final prefix = config.prefix.replaceAll(RegExp(r'^/+|/+$'), '');
    final key = [if (prefix.isNotEmpty) prefix, remoteFolderName, name].join('/');
    final encoded = _awsEncode(key, keepSlash: true);
    if (config.endpoint.isEmpty) {
      return Uri.parse('https://${config.bucket}.s3.${config.region}.amazonaws.com/$encoded');
    }
    final base = config.endpoint.contains('://') ? config.endpoint : 'https://${config.endpoint}';
    final u = Uri.parse(base);
    final path = [u.path.replaceAll(RegExp(r'/+$'), ''), config.bucket, encoded].join('/');
    return u.replace(path: path.startsWith('/') ? path : '/$path');
  }

  Future<(int, List<int>)> _request(String method, String name, [List<int>? body]) {
    final uri = _uri(name);
    final payloadHash = _hex(sha256.convert(body ?? const []).bytes);
    final host = uri.hasPort && uri.port != 443 && uri.port != 80 ? '${uri.host}:${uri.port}' : uri.host;
    final headers = {'host': host, 'x-amz-content-sha256': payloadHash};
    final signed = signV4(
      method: method,
      uri: uri,
      headers: headers,
      payloadHash: payloadHash,
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
      region: config.region,
    );
    return _send(
      _client,
      method,
      uri,
      headers: {
        'x-amz-content-sha256': payloadHash,
        ...signed,
        if (body != null) 'content-type': 'application/octet-stream',
      },
      body: body,
    );
  }

  @override
  Future<List<int>?> read(String name) async {
    final (status, body) = await _request('GET', name);
    if (status == 404) return null;
    if (status != 200) throw RemoteStoreException(_errorText(status, body));
    return body;
  }

  @override
  Future<void> write(String name, List<int> bytes) async {
    final (status, body) = await _request('PUT', name, bytes);
    if (status != 200 && status != 201 && status != 204) throw RemoteStoreException(_errorText(status, body));
  }

  @override
  Future<void> delete(String name) async {
    final (status, body) = await _request('DELETE', name);
    if (status != 200 && status != 204 && status != 404) throw RemoteStoreException(_errorText(status, body));
  }
}

// ---------------------------------------------------------------------------
// WebDAV (Nextcloud, ownCloud, pCloud, Koofr, Synology…)

final class WebDavRemoteStore implements RemoteStore {
  WebDavRemoteStore(this.config, {HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final CloudStorageConfig config;
  final HttpClient _client;

  Uri get _folder {
    final base = config.url.endsWith('/') ? config.url : '${config.url}/';
    return Uri.parse(base).resolve('${Uri.encodeComponent(remoteFolderName)}/');
  }

  Uri _uri(String name) => _folder.resolve(Uri.encodeComponent(name));

  Map<String, String> get _auth => config.username.isEmpty
      ? const {}
      : {'authorization': 'Basic ${base64.encode(utf8.encode('${config.username}:${config.password}'))}'};

  @override
  Future<List<int>?> read(String name) async {
    final (status, body) = await _send(_client, 'GET', _uri(name), headers: _auth);
    if (status == 404) return null;
    if (status != 200) throw RemoteStoreException(_errorText(status, body));
    return body;
  }

  @override
  Future<void> write(String name, List<int> bytes) async {
    var (status, body) = await _send(_client, 'PUT', _uri(name), headers: _auth, body: bytes);
    if (status == 404 || status == 409) {
      // The Local Board folder does not exist yet.
      final (mk, mkBody) = await _send(_client, 'MKCOL', _folder, headers: _auth);
      if (mk != 201 && mk != 405) throw RemoteStoreException(_errorText(mk, mkBody));
      (status, body) = await _send(_client, 'PUT', _uri(name), headers: _auth, body: bytes);
    }
    if (status < 200 || status > 299) throw RemoteStoreException(_errorText(status, body));
  }

  @override
  Future<void> delete(String name) async {
    final (status, body) = await _send(_client, 'DELETE', _uri(name), headers: _auth);
    if ((status < 200 || status > 299) && status != 404) throw RemoteStoreException(_errorText(status, body));
  }
}
