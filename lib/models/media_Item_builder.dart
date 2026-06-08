// ignore_for_file: file_names

import 'package:audio_service/audio_service.dart';
import '../models/thumbnail.dart';

class MediaItemBuilder {
  static MediaItem fromJson(dynamic json, {String? url}) {
    // 🟢 SAFE ARTIST PARSING 🟢
    String artistName = 'Unknown Artist';
    if (json['artists'] != null && json['artists'] is List && (json['artists'] as List).isNotEmpty) {
      final mapped = json['artists'].map((e) => e['name'] ?? '').toList().join(', ');
      if (mapped.isNotEmpty && mapped != 'null') {
        artistName = mapped;
      }
    }

    Map? album;
    if (json['album'] != null && json['album'] is Map) {
      album = json['album'];
    }

    // 🟢 HYPEROS-PROOF ART URI PARSING 🟢
    Uri? artUri;
    try {
      if (json["thumbnails"] != null && (json["thumbnails"] as List).isNotEmpty) {
        String rawUrl = json["thumbnails"][0]['url']?.toString() ?? "";
        if (rawUrl.isNotEmpty && rawUrl != 'null' && rawUrl != '[]') {
          if (rawUrl.startsWith('file:')) {
            artUri = Uri.file(Uri.parse(rawUrl).toFilePath(windows: false)); 
          } else {
            artUri = Uri.tryParse(Thumbnail(rawUrl).high);
          }
        }
      }
    } catch (_) {}

    // 🟢 SAFE DURATION PARSING (Prevents 'Null is not a subtype of int') 🟢
    Duration? songDuration;
    if (json['duration'] != null && json['duration'] is int) {
      songDuration = Duration(seconds: json['duration']);
    } else {
      songDuration = toDuration(json['length']);
    }

    return MediaItem(
        id: json["videoId"] ?? "",
        title: json["title"] ?? "Unknown Title",
        duration: songDuration,
        album: album != null ? album['name'] : null,
        artist: artistName,
        artUri: artUri,
        extras: {
          'url': json['url'] ?? url,
          'length': json['length'],
          'album': album,
          'artists': json['artists'],
          'date': json['date'],
          'trackDetails': json['trackDetails'],
          'year': json['year'],
          'isLocal': json['isLocal'] ?? false,
          'localPath': json['localPath'],
          'lyrics': json['lyrics'],
        });
  }

  static Duration? toDuration(String? time) {
    if (time == null) return null;

    int sec = 0;
    final splitted = time.split(":");
    if (splitted.length == 3) {
      sec += int.parse(splitted[0]) * 3600 + int.parse(splitted[1]) * 60 + int.parse(splitted[2]);
    } else if (splitted.length == 2) {
      sec += int.parse(splitted[0]) * 60 + int.parse(splitted[1]);
    } else if (splitted.length == 1) {
      sec += int.parse(splitted[0]);
    }
    return Duration(seconds: sec);
  }

  static Map<String, dynamic> toJson(MediaItem mediaItem) {
    String? thumbUrl = mediaItem.artUri?.toString();

    return {
      "videoId": mediaItem.id,
      "title": mediaItem.title,
      'album': mediaItem.extras?['album'] ?? (mediaItem.album != null ? {'name': mediaItem.album} : null),
      'artists': mediaItem.extras?['artists'] ?? (mediaItem.artist != null ? [{'name': mediaItem.artist}] : null),
      'length': mediaItem.extras?['length'],
      'duration': mediaItem.duration?.inSeconds,
      'date': mediaItem.extras?['date'],
      'thumbnails': (thumbUrl != null && thumbUrl != 'null') ? [{'url': thumbUrl}] : [],
      'url': mediaItem.extras?['url'],
      'trackDetails': mediaItem.extras?['trackDetails'],
      'year': mediaItem.extras?['year'],
      'isLocal': mediaItem.extras?['isLocal'] ?? false,
      'localPath': mediaItem.extras?['localPath'],
      'lyrics': mediaItem.extras?['lyrics'],
    };
  }
}