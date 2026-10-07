import 'package:yt_extractor/yt_extractor.dart';
import '../../utils/helper.dart'; 

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;
  StreamProvider({required this.playable, this.audioFormats, this.statusMSG = ""});

  static Future<StreamProvider> fetch(String videoId) async {
    if (videoId.trim().isEmpty || videoId.startsWith("local_")) {
      return StreamProvider(playable: false, statusMSG: "Invalid or Local Song ID");
    }

    printINFO("🔄 [STREAM] Using Native NewPipe Extractor (SimpMusic Engine)...");

    try {
      final extractor = YtExtractor();
      
      // 🟢 THE FIX: NewPipe expects a FULL URL, not just the video ID 🟢
      final fullUrl = "https://www.youtube.com/watch?v=$videoId";
      final streamInfo = await extractor.getStreamInfo(fullUrl);

      if (streamInfo != null && streamInfo.audioStreams.isNotEmpty) {
        printINFO("🎉 [STREAM] NewPipe extraction succeeded!");
        
        // Sort by bitrate (highest first)
        final sortedStreams = streamInfo.audioStreams.toList()
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

        return StreamProvider(
          playable: true,
          statusMSG: "OK",
          audioFormats: sortedStreams.map((stream) => Audio(
            itag: stream.itag,
            audioCodec: stream.format?.contains('mp4') == true ? Codec.mp4a : Codec.opus,
            bitrate: stream.bitrate,
            duration: streamInfo.duration * 1000, 
            loudnessDb: 0.0,
            url: stream.url,
            size: 0, 
            userAgent: 'com.google.android.youtube/19.28.39 (Linux; U; Android 14) gzip', 
          )).toList(),
        );
      }
    } catch (e) {
      printINFO("⚠️ [STREAM] NewPipe extraction failed: $e");
    }

    return StreamProvider(playable: false, statusMSG: "Extraction failed.");
  }

  Audio? get highestQualityAudio => audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 140, orElse: () => audioFormats!.first);
  Audio? get highestBitrateMp4aAudio => audioFormats?.lastWhere((item) => item.itag == 140 || item.itag == 139, orElse: () => audioFormats!.first);
  Audio? get highestBitrateOpusAudio => audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 250, orElse: () => audioFormats!.first);
  Audio? get lowQualityAudio => audioFormats?.lastWhere((item) => item.itag == 249 || item.itag == 139, orElse: () => audioFormats!.first);

  Map<String, dynamic> get hmStreamingData {
    return {
      "playable": playable, 
      "statusMSG": statusMSG, 
      "lowQualityAudio": lowQualityAudio?.toJson(), 
      "highQualityAudio": highestQualityAudio?.toJson()
    };
  }
}

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;
  final String userAgent;

  Audio({
    required this.itag,
    required this.audioCodec,
    required this.bitrate,
    required this.duration,
    required this.loudnessDb,
    required this.url,
    required this.size,
    this.userAgent = 'com.google.android.youtube/19.28.39 (Linux; U; Android 14) gzip',
  });

  Map<String, dynamic> toJson() => {
        "itag": itag,
        "audioCodec": audioCodec.toString(),
        "bitrate": bitrate,
        "loudnessDb": loudnessDb,
        "url": url,
        "approxDurationMs": duration,
        "size": size,
        "userAgent": userAgent,
      };

  factory Audio.fromJson(Map<String, dynamic> json) => Audio(
      audioCodec: (json["audioCodec"] as String).contains("mp4a") ? Codec.mp4a : Codec.opus,
      itag: int.tryParse(json['itag'].toString()) ?? 0,
      duration: int.tryParse(json["approxDurationMs"].toString()) ?? 0,
      bitrate: int.tryParse(json["bitrate"].toString()) ?? 0,
      loudnessDb: (json['loudnessDb'] is num) ? (json['loudnessDb'] as num).toDouble() : 0.0,
      url: json['url']?.toString() ?? "",
      size: int.tryParse(json["size"].toString()) ?? 0,
      userAgent: json['userAgent']?.toString() ?? 'com.google.android.youtube/19.28.39 (Linux; U; Android 14) gzip',
  );
}

enum Codec { mp4a, opus }