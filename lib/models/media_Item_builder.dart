// ignore_for_file: file_names

import 'package:audio_service/audio_service.dart';
import '../models/thumbnail.dart';

class MediaItemBuilder {
  static MediaItem fromJson(dynamic json, {String? url}) {
    String? artistName;
    if (json['artists'] != null && json['artists'] is List && (json['artists'] as List).isNotEmpty) {
      artistName = json['artists'].map((e) => e['name']).toList().join(', ').toString();
    }

    Map? album;
    if (json['album'] != null && json['album'] is Map) {
      album = json['album'];
    }

    // 🟢 SAFELY PARSE ART URI (Protects local file:// paths) 🟢
    Uri? artUri;
    try {
      if (json["thumbnails"] != null && (json["thumbnails"] as List).isNotEmpty && json["thumbnails"][0]['url'] != null) {
        String rawUrl = json["thumbnails"][0]['url'].toString();
        if (rawUrl.startsWith('file:')) {
          artUri = Uri.parse(rawUrl); // Keep local file paths exactly as they are!
        } else if (rawUrl != 'null' && rawUrl.isNotEmpty) {
          artUri = Uri.parse(Thumbnail(rawUrl).high); // Use YouTube resizer for web images
        }
      }
    } catch (_) {}

    return MediaItem(
        id: json["videoId"] ?? "",
        title: json["title"] ?? "Unknown Title",
        duration: json['duration'] != null
            ? Duration(seconds: json['duration'])
            : toDuration(json['length']),
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
          // 🟢 RESTORE LOCAL SONG FLAGS 🟢
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
    // 🟢 SAFELY EXTRACT ART URI 🟢
    String? thumbUrl = mediaItem.artUri?.toString();

    return {
      "videoId": mediaItem.id,
      "title": mediaItem.title,
      // Fallback to mediaItem.album/artist if extras doesn't have them (crucial for local songs)
      'album': mediaItem.extras?['album'] ?? (mediaItem.album != null ? {'name': mediaItem.album} : null),
      'artists': mediaItem.extras?['artists'] ?? (mediaItem.artist != null ? [{'name': mediaItem.artist}] : null),
      'length': mediaItem.extras?['length'],
      'duration': mediaItem.duration?.inSeconds,
      'date': mediaItem.extras?['date'],
      'thumbnails': (thumbUrl != null && thumbUrl != 'null') ? [{'url': thumbUrl}] : [],
      'url': mediaItem.extras?['url'],
      'trackDetails': mediaItem.extras?['trackDetails'],
      'year': mediaItem.extras?['year'],
      // 🟢 SAVE LOCAL SONG FLAGS TO DATABASE 🟢
      'isLocal': mediaItem.extras?['isLocal'] ?? false,
      'localPath': mediaItem.extras?['localPath'],
      'lyrics': mediaItem.extras?['lyrics'],
    };
  }
}