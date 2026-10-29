import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../supervision/presentation/adult_access_dialog.dart';
import '../../supervision/presentation/sensitive_action.dart';
import '../data/backup_service.dart';

Future<void> confirmBackupRestore(
  BuildContext context,
  AppServices services,
  BackupPreview preview,
) async {
  if (!await confirm(
    context,
    '恢复备份',
    '${preview.sourceCount} 个来源、${preview.historyCount} 条观看记录。确认替换当前设置、源和历史？损坏的数据会回滚。',
  )) {
    return;
  }
  if (!context.mounted) return;
  if (preview.disablesAdultFilter &&
      !await verifyAdultFilterAccess(
        context,
        services.installationAccess,
        restoringBackup: true,
      )) {
    return;
  }
  if (!context.mounted) return;
  if (!await runSensitive(
    context,
    services.supervision,
    SensitiveOperation.restore,
    () => services.restoreBackup(preview),
  )) {
    return;
  }
  if (context.mounted) message(context, '备份已恢复');
}
