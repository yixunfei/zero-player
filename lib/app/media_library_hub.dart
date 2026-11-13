import 'package:flutter/material.dart';
import 'dart:async';
import 'app_services.dart';
import '../features/books/domain/book.dart';
import '../features/books/presentation/books_page.dart';
import '../features/downloads/presentation/downloads_page.dart';
import '../features/library/presentation/history_page.dart';
import '../features/music/presentation/music_library_panel.dart';

class MediaLibraryHub extends StatefulWidget {
  const MediaLibraryHub({
    super.key,
    required this.services,
    required this.downloads,
  });
  final AppServices services;
  final bool downloads;
  @override
  State<MediaLibraryHub> createState() => _MediaLibraryHubState();
}

class _MediaLibraryHubState extends State<MediaLibraryHub> {
  AppServices get services => widget.services;
  bool get downloads => widget.downloads;
  @override
  void initState() {
    super.initState();
    unawaited(services.musicLibrary.load());
    unawaited(services.musicDownloads.load());
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: '影音'),
            Tab(text: '音乐'),
            Tab(text: '阅读'),
            Tab(text: '听书'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              downloads
                  ? DownloadsPage(services: services)
                  : HistoryPage(services: services),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: MusicLibraryPanel(
                  services: services,
                  view: downloads ? 'downloads' : 'history',
                ),
              ),
              BooksPage(
                services: services,
                kind: BookKind.text,
                initialTab: 1,
                libraryMode: downloads ? 'downloads' : 'history',
              ),
              BooksPage(
                services: services,
                kind: BookKind.audio,
                initialTab: 1,
                libraryMode: downloads ? 'downloads' : 'history',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
