import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
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

    printINFO("🔄 [STREAM] Attempting Native Extraction with Android Client...");

    try {
      final yt = YoutubeExplode();
      // 🟢 FORCE ANDROID CLIENT FOR MOST RELIABLE URL GENERATION 🟢
      final res = await yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.android], 
      );
      
      final audio = res.audioOnly;
      final validAudio = audio.where((e) {
        final urlStr = e.url.toString();
        return urlStr.isNotEmpty && urlStr.startsWith('http') && !urlStr.contains('.m3u8');
      }).toList();

      if (validAudio.isNotEmpty) {
        printINFO("🎉 [STREAM] Native extraction succeeded with Android client!");
        return StreamProvider(
            playable: true,
            statusMSG: "OK",
            audioFormats: validAudio.map((e) => Audio(
                itag: e.tag,
                audioCodec: e.audioCodec.contains('mp') ? Codec.mp4a : Codec.opus,
                bitrate: e.bitrate.bitsPerSecond,
                duration: 0,
                loudnessDb: 0.0,
                url: e.url.toString(),
                size: e.size.totalBytes,
                // 🟢 THIS IS THE MAGIC KEY: MATCH THE CLIENT IDENTITY 🟢
                userAgent: 'com.google.android.youtube/19.09.3 (Linux; U; Android 11) gzip', 
            )).toList());
      }
    } catch (e) {
      printINFO("⚠️ [STREAM] Native extraction failed: $e");
    }

    // ==========================================
    // FALLBACK: Cobalt API (Corrected v10 Payload)
    // ==========================================
    printINFO("🔄 [STREAM] Native failed. Falling back to Cobalt API...");
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ));

      final response = await dio.post(
        "https://api.cobalt.tools/",
        data: {
          "url": "https://www.youtube.com/watch?v=$videoId",
          "downloadMode": "audio",
          "audioFormat": "mp3"
        },
      );

      if (response.statusCode == 200 && response.data is Map && response.data['url'] != null) {
        printINFO("🎉 [STREAM] Cobalt fallback succeeded!");
        return StreamProvider(
          playable: true,
          statusMSG: "OK",
          audioFormats: [
            Audio(
              itag: 0,
              audioCodec: Codec.mp4a,
              bitrate: 128000,
              duration: 0,
              loudnessDb: 0.0,
              url: response.data['url'].toString(),
              size: 0,
              userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            )
          ],
        );
      }
    } catch (e) {
      printINFO("⚠️ [STREAM] Cobalt fallback failed: $e");
    }

    return StreamProvider(playable: false, statusMSG: "All extraction methods blocked.");
  }

  Audio? get highestQualityAudio => audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 140, orElse: () => audioFormats!.first);
  Audio? get highestBitrateMp4aAudio => audioFormats?.lastWhere((item) => item.itag == 140 || item.itag == 139, orElse: () => audioFormats!.first);
  Audio? get highestBitrateOpusAudio => audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 250, orElse: () => audioFormats!.first);
  Audio? get lowQualityAudio => audioFormats?.lastWhere((item) => item.itag == 249 || item.itag == 139, orElse: () => audioFormats!.first);

  Map<String, dynamic> get hmStreamingData {
    return {"playable": playable, "statusMSG": statusMSG, "lowQualityAudio": lowQualityAudio?.toJson(), "highQualityAudio": highestQualityAudio?.toJson()};
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
  final String userAgent; // 🟢 NEW FIELD TO STORE THE IDENTITY 🟢

  Audio({
    required this.itag,
    required this.audioCodec,
    required this.bitrate,
    required this.duration,
    required this.loudnessDb,
    required this.url,
    required this.size,
    this.userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36', // Default fallback
  });

  Map<String, dynamic> toJson() => {
        "itag": itag,
        "audioCodec": audioCodec.toString(),
        "bitrate": bitrate,
        "loudnessDb": loudnessDb,
        "url": url,
        "approxDurationMs": duration,
        "size": size,
        "userAgent": userAgent, // 🟢 SAVE IT TO JSON 🟢
      };

  factory Audio.fromJson(json) => Audio(
      audioCodec: (json["audioCodec"] as String).contains("mp4a") ? Codec.mp4a : Codec.opus,
      itag: int.tryParse(json['itag'].toString()) ?? 0,
      duration: int.tryParse(json["approxDurationMs"].toString()) ?? 0,
      bitrate: int.tryParse(json["bitrate"].toString()) ?? 0,
      loudnessDb: (json['loudnessDb'] is num) ? (json['loudnessDb'] as num).toDouble() : 0.0,
      url: json['url']?.toString() ?? "",
      size: int.tryParse(json["size"].toString()) ?? 0,
      userAgent: json['userAgent']?.toString() ?? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36', // 🟢 READ IT FROM JSON 🟢
  );
}

enum Codec { mp4a, opus }