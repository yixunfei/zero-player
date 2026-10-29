import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/persistence/installation_metadata.dart';
import 'package:zero_player/features/supervision/application/installation_access.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';

void main() {
  late Directory root;
  late AppServices services;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('filter-authorization-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      installationAccessKey,
      upgradedInstallationAccess,
    ]);
    await services.supervision.load();
    await services.settings.load();
    final guard = services.supervision;
    await guard.saveCredentials(
      await guard.prepareCredentials('test-password'),
    );
  });
  tearDown(() async {
    await services.close();
    await root.delete(recursive: true);
  });
  test(
    'default policy permits content changes but still locks adult filtering',
    () async {
      expect(services.installationAccess.protectContentFilter, isFalse);
      await services.settings.update({
        'contentFilter': false,
        'filterOcr': false,
        'filterAsr': false,
        'filterKeywords': false,
        'filterSkipSeconds': 30,
        'filterStrategy': 'confirm',
      });
      expect(services.settings.value.filterSkipSeconds, 30);
      await services.filterFeatures.remove('nonexistent-rule');
      expect(services.installationAccess.adultVerified, isTrue);
      await expectLater(
        services.settings.update({'filterAdult': false}),
        throwsFormatException,
      );
      expect(services.contentPolicy.filterAdult, isTrue);
    },
  );
  test(
    'protection guards settings and rule changes and survives reload',
    () async {
      final guard = services.supervision;
      final access = services.installationAccess;
      await guard.execute(
        SensitiveOperation.supervision,
        () => access.setContentFilterProtection(true),
        password: 'test-password',
      );
      for (final key in [
        'contentFilter',
        'filterOcr',
        'filterAsr',
        'filterKeywords',
      ]) {
        await expectLater(
          services.settings.update({key: false}),
          throwsFormatException,
        );
      }
      await expectLater(
        services.settings.update({'filterSkipSeconds': 30}),
        throwsFormatException,
      );
      await expectLater(
        services.filterFeatures.remove('rule'),
        throwsFormatException,
      );
      await guard.execute(
        SensitiveOperation.contentFilter,
        () => services.settings.update({'filterSkipSeconds': 30}),
        password: 'test-password',
      );
      expect(services.settings.value.filterSkipSeconds, 30);
      await expectLater(
        access.setContentFilterProtection(false),
        throwsFormatException,
      );
      final reloaded = InstallationAccess(services.db);
      await reloaded.load();
      expect(reloaded.protectContentFilter, isTrue);
      await reloaded.close();
      await guard.execute(
        SensitiveOperation.supervision,
        () => access.setContentFilterProtection(false),
        password: 'test-password',
      );
      await services.settings.update({'filterSkipSeconds': 20});
      await services.filterFeatures.remove('rule');
    },
  );
}
