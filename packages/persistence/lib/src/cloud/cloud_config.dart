import 'dart:io';

import 'package:path/path.dart' as p;

/// How Local Board talks to a storage.
enum CloudKind {
  /// A folder kept in sync by the provider's own desktop app. Works offline
  /// and needs no password in Local Board.
  folder,

  /// Amazon S3 or any S3-compatible service.
  s3,

  /// WebDAV server (Nextcloud, ownCloud, pCloud, Koofr…).
  webdav,
}

enum CloudProvider {
  googleDrive('Google Drive', CloudKind.folder),
  oneDrive('OneDrive', CloudKind.folder),
  protonDrive('Proton Drive', CloudKind.folder),
  dropbox('Dropbox', CloudKind.folder),
  iCloudDrive('iCloud Drive', CloudKind.folder),
  s3('Amazon S3 and compatible', CloudKind.s3),
  webdav('WebDAV', CloudKind.webdav),
  folder('Any synced folder', CloudKind.folder);

  const CloudProvider(this.label, this.kind);

  final String label;
  final CloudKind kind;
}

/// One configured storage. Settings are plain strings so new providers do
/// not need a new file format.
final class CloudStorageConfig {
  const CloudStorageConfig({
    required this.id,
    required this.provider,
    this.enabled = true,
    this.values = const {},
    this.lastSync,
    this.lastError,
  });

  final String id;
  final CloudProvider provider;
  final bool enabled;
  final Map<String, String> values;
  final DateTime? lastSync;
  final String? lastError;

  String value(String key) => values[key] ?? '';

  // Folder
  String get folder => value('folder');

  // S3
  String get endpoint => value('endpoint');
  String get region => value('region').isEmpty ? 'us-east-1' : value('region');
  String get bucket => value('bucket');
  String get prefix => value('prefix');
  String get accessKeyId => value('accessKeyId');
  String get secretAccessKey => value('secretAccessKey');

  // WebDAV
  String get url => value('url');
  String get username => value('username');
  String get password => value('password');

  /// Short description for lists, e.g. the folder or bucket.
  String get summary => switch (provider.kind) {
    CloudKind.folder => folder,
    CloudKind.s3 => [bucket, if (prefix.isNotEmpty) prefix].join('/'),
    CloudKind.webdav => url,
  };

  /// What is missing before this storage can be used, or null.
  String? get problem => switch (provider.kind) {
    CloudKind.folder => folder.isEmpty ? 'Choose a folder' : null,
    CloudKind.s3 =>
      bucket.isEmpty || accessKeyId.isEmpty || secretAccessKey.isEmpty ? 'Bucket and access keys are required' : null,
    CloudKind.webdav => Uri.tryParse(url)?.hasScheme != true ? 'Enter the server address' : null,
  };

  CloudStorageConfig copyWith({
    bool? enabled,
    Map<String, String>? values,
    DateTime? Function()? lastSync,
    String? Function()? lastError,
  }) => CloudStorageConfig(
    id: id,
    provider: provider,
    enabled: enabled ?? this.enabled,
    values: values ?? this.values,
    lastSync: lastSync != null ? lastSync() : this.lastSync,
    lastError: lastError != null ? lastError() : this.lastError,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'provider': provider.name,
    'enabled': enabled,
    'values': values,
    if (lastSync != null) 'lastSync': lastSync!.toUtc().toIso8601String(),
    if (lastError != null) 'lastError': lastError,
  };

  static CloudStorageConfig? tryParse(Object? json) {
    if (json is! Map) return null;
    final provider = CloudProvider.values.asNameMap()[json['provider']];
    final id = json['id'];
    if (provider == null || id is! String) return null;
    final values = json['values'];
    return CloudStorageConfig(
      id: id,
      provider: provider,
      enabled: json['enabled'] != false,
      values: {
        if (values is Map)
          for (final e in values.entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String,
      },
      lastSync: json['lastSync'] is String ? DateTime.tryParse(json['lastSync'] as String) : null,
      lastError: json['lastError'] is String ? json['lastError'] as String : null,
    );
  }
}

/// Folders where the provider's desktop app usually keeps its files, that
/// exist on this computer. The user can always pick another one.
List<String> suggestedFolders(CloudProvider provider, {Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final home = env['USERPROFILE'] ?? env['HOME'] ?? '';
  final candidates = <String>[];
  List<String> children(String dir, String sub) {
    try {
      return [
        for (final e in Directory(dir).listSync())
          if (e is Directory) p.join(e.path, sub),
      ];
    } on Object {
      return const [];
    }
  }

  switch (provider) {
    case CloudProvider.googleDrive:
      if (Platform.isWindows) {
        for (var c = 'D'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
          candidates.add('${String.fromCharCode(c)}:\\My Drive');
        }
      }
      candidates.addAll([
        p.join(home, 'Google Drive', 'My Drive'),
        p.join(home, 'Google Drive'),
        p.join(home, 'GoogleDrive'),
        p.join(home, 'google-drive'),
      ]);
    case CloudProvider.oneDrive:
      for (final k in ['OneDrive', 'OneDriveConsumer', 'OneDriveCommercial']) {
        final v = env[k];
        if (v != null && v.isNotEmpty) candidates.add(v);
      }
      candidates.add(p.join(home, 'OneDrive'));
    case CloudProvider.protonDrive:
      candidates.addAll(children(p.join(home, 'Proton Drive'), 'My files'));
      candidates.addAll([p.join(home, 'Proton Drive'), p.join(home, 'ProtonDrive')]);
    case CloudProvider.dropbox:
      candidates.add(p.join(home, 'Dropbox'));
    case CloudProvider.iCloudDrive:
      candidates.addAll([
        p.join(home, 'iCloudDrive'),
        p.join(home, 'Library', 'Mobile Documents', 'com~apple~CloudDocs'),
      ]);
    case CloudProvider.s3:
    case CloudProvider.webdav:
    case CloudProvider.folder:
      break;
  }
  final seen = <String>{};
  return [
    for (final c in candidates)
      if (seen.add(p.normalize(c).toLowerCase()) && Directory(c).existsSync()) c,
  ];
}
