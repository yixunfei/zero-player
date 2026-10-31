enum DownloadStatus {
  queued,
  running,
  pendingSave,
  saving,
  paused,
  failed,
  complete,
}

final class DownloadTask {
  const DownloadTask(this.row);
  final Map<String, Object?> row;
  String get id => row['id'] as String;
  String get title => row['title'] as String;
  Uri get uri => Uri.parse(row['url'] as String);
  String get directory => row['directory'] as String;
  String? get localPath => row['local_path'] as String?;
  String? get error => row['error'] as String?;
  DownloadStatus get status =>
      DownloadStatus.values.byName(row['status'] as String);
  int get completed => row['completed'] as int;
  int get total => row['total'] as int;
  int get bytes => row['bytes'] as int;
}
