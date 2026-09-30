import 'dart:convert';
import 'dart:io';

import 'package:local_board_core/local_board_core.dart';
import 'package:local_board_persistence/local_board_persistence.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

StrokeObject stroke(String id) =>
    StrokeObject(id: id, points: const [Vec2(0, 0), Vec2(5, 5)], color: 0xFF000000, width: 2);

/// Remote kept in memory, counting what sync sends.
final class MemoryRemote implements RemoteStore {
  final files = <String, List<int>>{};
  int writes = 0;

  @override
  Future<List<int>?> read(String name) async => files[name];

  @override
  Future<void> write(String name, List<int> bytes) async {
    writes++;
    files[name] = bytes;
  }

  @override
  Future<void> delete(String name) async => files.remove(name);
}

void main() {
  late Directory tmp;
  late BoardStore laptop, desktop;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lb_cloud_');
    laptop = BoardStore(Directory(p.join(tmp.path, 'laptop')));
    desktop = BoardStore(Directory(p.join(tmp.path, 'desktop')));
  });

  tearDown(() => tmp.delete(recursive: true));

  group('settings', () {
    test('round-trip and defaults', () async {
      final store = SettingsStore(tmp);
      expect((await store.load()).checkForUpdates, isTrue);
      final s = const AppSettings()
          .withPlugin('network-architecture', enabled: false)
          .copyWith(checkForUpdates: false, skippedVersion: () => '0.3.0')
          .withStorage(
            const CloudStorageConfig(id: 'a', provider: CloudProvider.s3, values: {'bucket': 'b', 'accessKeyId': 'k'}),
          );
      await store.save(s);
      final back = await store.load();
      expect(back.isPluginEnabled('network-architecture'), isFalse);
      expect(back.isPluginEnabled('software-architecture'), isTrue);
      expect(back.checkForUpdates, isFalse);
      expect(back.skippedVersion, '0.3.0');
      expect(back.storages.single.bucket, 'b');
      expect(back.storages.single.problem, isNotNull); // secret key missing
      expect(back.withoutStorage('a').storages, isEmpty);
    });

    test('a damaged settings file falls back to defaults', () async {
      final store = SettingsStore(tmp);
      await store.file.writeAsString('{not json');
      expect((await store.load()).storages, isEmpty);
      expect(AppSettings.fromJson({'storages': [{'provider': 'nope'}], 'checkForUpdates': 'x'}).checkForUpdates, isTrue);
    });
  });

  group('sync', () {
    test('boards travel between two computers through a synced folder', () async {
      final folder = FolderRemoteStore(Directory(p.join(tmp.path, 'Drive', remoteFolderName)));
      await Directory(p.join(tmp.path, 'Drive')).create();

      final doc = await laptop.create(title: 'Roadmap');
      History(doc).execute(AddObjects([stroke('a')]));
      await laptop.save(doc);

      final first = await syncBoards(laptop, folder);
      expect(first.uploaded, 1);
      final second = await syncBoards(desktop, folder);
      expect(second.downloaded, 1);
      final there = (await desktop.open(doc.id)).document;
      expect(there.title, 'Roadmap');
      expect(there.length, 1);

      // Edit on the desktop, sync back to the laptop.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      History(there).execute(AddObjects([stroke('b')]));
      await desktop.save(there);
      expect((await syncBoards(desktop, folder)).uploaded, 1);
      expect((await syncBoards(laptop, folder)).downloaded, 1);
      expect((await laptop.open(doc.id)).document.length, 2);

      // Nothing changed: nothing is transferred.
      final idle = await syncBoards(laptop, folder);
      expect(idle.uploaded + idle.downloaded, 0);
    });

    test('open boards are never replaced underneath the editor', () async {
      final remote = MemoryRemote();
      final doc = await laptop.create(title: 'Open');
      await syncBoards(laptop, remote);
      await syncBoards(desktop, remote);
      final there = (await desktop.open(doc.id)).document;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      History(there).execute(AddObjects([stroke('x')]));
      await desktop.save(there);
      await syncBoards(desktop, remote);
      final report = await syncBoards(laptop, remote, busy: {doc.id});
      expect(report.downloaded, 0);
      expect((await laptop.open(doc.id)).document.length, 0);
    });

    test('moving a board to the trash reaches the other computer', () async {
      final remote = MemoryRemote();
      final doc = await laptop.create(title: 'Old idea');
      await syncBoards(laptop, remote);
      await syncBoards(desktop, remote);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await laptop.moveToTrash(doc.id);
      expect((await syncBoards(laptop, remote)).deletedThere, 1);
      expect(remote.files.containsKey('${doc.id}.whiteboard'), isFalse);
      expect((await syncBoards(desktop, remote)).trashedHere, 1);
      expect(await desktop.list(), isEmpty);
      expect(await desktop.trashed(), contains(doc.id));
    });

    test('boards from a newer app are skipped, not broken', () async {
      final remote = MemoryRemote();
      final json = BoardDocument.create(title: 'Future').toJson()..['schemaVersion'] = currentSchemaVersion + 1;
      remote.files['${json['boardId']}.whiteboard'] = utf8.encode(jsonEncode(json));
      remote.files[manifestName] = utf8.encode(
        jsonEncode({
          'boards': {
            json['boardId']: {'updatedAt': DateTime.now().toUtc().toIso8601String(), 'title': 'Future'},
          },
        }),
      );
      final report = await syncBoards(desktop, remote);
      expect(report.needsUpdate, 1);
      expect(await desktop.list(), isEmpty);
    });

    test('a folder whose provider is missing gives a clear error', () async {
      final missing = FolderRemoteStore(Directory(p.join(tmp.path, 'NoDrive', remoteFolderName)));
      expect(() => testRemoteStore(missing), throwsA(isA<RemoteStoreException>()));
      final ok = FolderRemoteStore(Directory(p.join(tmp.path, remoteFolderName)));
      await testRemoteStore(ok);
    });
  });

  group('S3 signing', () {
    test('matches the AWS Signature V4 reference request', () {
      final h = signV4(
        method: 'GET',
        uri: Uri.parse('https://example.amazonaws.com/'),
        headers: {'host': 'example.amazonaws.com'},
        payloadHash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        accessKeyId: 'AKIDEXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
        region: 'us-east-1',
        service: 'service',
        now: DateTime.utc(2015, 8, 30, 12, 36),
      );
      expect(h['x-amz-date'], '20150830T123600Z');
      expect(
        h['authorization'],
        'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, '
        'SignedHeaders=host;x-amz-date, '
        'Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31',
      );
    });
  });
}
