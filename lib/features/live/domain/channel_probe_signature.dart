import 'dart:convert';
import '../../sources/domain/video_source.dart';
import 'live_channel.dart';

/// A changed URL or scoped request header must invalidate prior evidence.
String channelProbeSignature(LiveChannel channel) => stableId(
  jsonEncode([
    for (final uri in channel.urls)
      [
        uri.toString(),
        {
          for (final key in channel.headersFor(uri).keys.toList()..sort())
            key.toLowerCase(): channel.headersFor(uri)[key],
        },
      ],
  ]),
);
