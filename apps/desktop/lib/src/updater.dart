import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const releasesRepo = 'dev-fcastro/local-board';
const releasesPage = 'https://github.com/$releasesRepo/releases';

/// A published release, from the GitHub API.
final class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.notes, required this.page, required this.assets});

  /// Without the leading "v".
  final String version;
  final String notes;
  final String page;

  /// File name → download URL.
  final Map<String, String> assets;

  static ReleaseInfo? fromJson(Object? json) {
    if (json is! Map || json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String) return null;
    final assets = json['assets'];
    return ReleaseInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      notes: json['body'] is String ? json['body'] as String : '',
      page: json['html_url'] is String ? json['html_url'] as String : releasesPage,
      assets: {
        if (assets is List)
          for (final a in assets)
            if (a is Map && a['name'] is String && a['browser_download_url'] is String)
              a['name'] as String: a['browser_download_url'] as String,
      },
    );
  }
}

/// Compares dotted versions numerically ("0.10.0" > "0.9.3").
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final s in v.split('+').first.split('.')) int.tryParse(s) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// How this copy of Local Board was installed, which decides how it updates.
enum InstallKind {
  /// Installed with the Windows setup: run the new setup silently.
  windowsInstaller,

  /// Running as an AppImage: replace the file.
  appImage,

  /// Installed with install.sh into ~/.local/opt: replace the folder.
  linuxUserInstall,

  /// Portable copy or development build: open the download page.
  manual;

  bool get automatic => this != manual;
}

InstallKind detectInstallKind({String? executable, Map<String, String>? environment}) {
  final exe = executable ?? Platform.resolvedExecutable;
  final env = environment ?? Platform.environment;
  final dir = p.dirname(exe);
  if (Platform.isWindows) {
    return File(p.join(dir, 'unins000.exe')).existsSync() ? InstallKind.windowsInstaller : InstallKind.manual;
  }
  if (Platform.isLinux) {
    final appImage = env['APPIMAGE'];
    if (appImage != null && appImage.isNotEmpty) return InstallKind.appImage;
    final home = env['HOME'] ?? '';
    if (home.isNotEmpty && p.isWithin(p.join(home, '.local', 'opt', 'local-board'), exe)) {
      return InstallKind.linuxUserInstall;
    }
  }
  return InstallKind.manual;
}

/// The release file this kind of install needs.
String? assetFor(InstallKind kind, String version) => switch (kind) {
  InstallKind.windowsInstaller => 'LocalBoard-$version-Setup-x64.exe',
  InstallKind.appImage => 'LocalBoard-$version-x86_64.AppImage',
  InstallKind.linuxUserInstall => 'LocalBoard-$version-linux-x86_64.tar.gz',
  InstallKind.manual => null,
};

/// Parses a `sha256sum` file into name → hash.
Map<String, String> parseChecksums(String text) => {
  for (final line in const LineSplitter().convert(text))
    if (RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line.trim()) case final m?)
      m.group(2)!.trim(): m.group(1)!.toLowerCase(),
};

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Checks GitHub for new releases and installs them. Only talks to
/// github.com, and only when asked (on startup if enabled, or "Check now").
class Updater {
  Updater({required this.currentVersion, HttpClient? client, InstallKind? kind})
    : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15)),
      kind = kind ?? detectInstallKind();

  final String currentVersion;
  final InstallKind kind;
  final HttpClient _client;

  Map<String, String> get _headers => {'user-agent': 'LocalBoard/$currentVersion', 'accept': 'application/vnd.github+json'};

  /// The latest release if it is newer than this one, otherwise null.
  Future<ReleaseInfo?> check() async {
    final req = await _client
        .getUrl(Uri.parse('https://api.github.com/repos/$releasesRepo/releases/latest'))
        .timeout(const Duration(seconds: 20));
    _headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 404) return null; // nothing published yet
    if (res.statusCode != 200) throw UpdateException('GitHub answered ${res.statusCode}. Try again later.');
    final release = ReleaseInfo.fromJson(jsonDecode(body));
    if (release == null || compareVersions(release.version, currentVersion) <= 0) return null;
    return release;
  }

  Future<List<int>> _download(String url, {void Function(double)? onProgress}) async {
    final req = await _client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 30));
    req.headers.set('user-agent', 'LocalBoard/$currentVersion');
    final res = await req.close();
    if (res.statusCode != 200) throw UpdateException('Download failed (${res.statusCode}).');
    final total = res.contentLength;
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.timeout(const Duration(seconds: 60))) {
      out.add(chunk);
      if (total > 0) onProgress?.call(out.length / total);
    }
    return out.takeBytes();
  }

  /// Downloads the new version, checks it against the release's SHA256SUMS
  /// and installs it. Returns the program to start once this one exits.
  Future<(String, List<String>)> prepare(ReleaseInfo release, {void Function(double)? onProgress}) async {
    final name = assetFor(kind, release.version);
    final url = name == null ? null : release.assets[name];
    final sumsUrl = release.assets['SHA256SUMS'];
    if (url == null || sumsUrl == null) {
      throw const UpdateException('This release has no automatic update for this system. Download it from the website.');
    }
    final sums = parseChecksums(utf8.decode(await _download(sumsUrl)));
    final bytes = await _download(url, onProgress: onProgress);
    final expected = sums[name];
    if (expected == null || sha256.convert(bytes).toString() != expected) {
      throw const UpdateException('The download did not match its checksum, so it was not installed.');
    }

    switch (kind) {
      case InstallKind.windowsInstaller:
        final dir = await Directory.systemTemp.createTemp('local-board-update-');
        final setup = File(p.join(dir.path, name!));
        await setup.writeAsBytes(bytes, flush: true);
        // The setup closes this app if needed and starts the new version.
        return (setup.path, const ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS']);
      case InstallKind.appImage:
        final target = Platform.environment['APPIMAGE']!;
        final tmp = File('$target.update');
        await tmp.writeAsBytes(bytes, flush: true);
        await Process.run('chmod', ['+x', tmp.path]);
        await tmp.rename(target); // the running copy keeps its old inode
        return (target, const <String>[]);
      case InstallKind.linuxUserInstall:
        final opt = p.dirname(Platform.resolvedExecutable);
        final staging = Directory('$opt.update');
        if (await staging.exists()) await staging.delete(recursive: true);
        await staging.create(recursive: true);
        final archive = File(p.join(staging.path, name!));
        await archive.writeAsBytes(bytes, flush: true);
        final tar = await Process.run('tar', ['-xzf', archive.path, '-C', staging.path]);
        final fresh = Directory(p.join(staging.path, 'local-board'));
        if (tar.exitCode != 0 || !await File(p.join(fresh.path, 'local-board')).exists()) {
          throw const UpdateException('The downloaded archive could not be unpacked.');
        }
        final old = Directory('$opt.old');
        if (await old.exists()) await old.delete(recursive: true);
        await Directory(opt).rename(old.path);
        await fresh.rename(opt);
        unawaited(staging.delete(recursive: true).then((_) => old.delete(recursive: true)).catchError((_) => old));
        return (p.join(opt, 'local-board'), const <String>[]);
      case InstallKind.manual:
        throw const UpdateException('Download the new version from the website.');
    }
  }

  /// Starts [program] on its own and quits this app.
  static Future<Never> relaunch((String, List<String>) program) async {
    await Process.start(program.$1, program.$2, mode: ProcessStartMode.detached);
    exit(0);
  }
}
