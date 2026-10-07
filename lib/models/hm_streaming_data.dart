import 'package:harmonymusic/services/stream_service.dart'show Audio;

class HMStreamingData {
  final bool playable;
  final String statusMSG;
  final Audio? lowQualityAudio;
  final Audio? highQualityAudio;
  int qualityIndex = 1;
  HMStreamingData({
    required this.playable,
    required this.statusMSG,
    this.lowQualityAudio,
    this.highQualityAudio,
  });

  setQualityIndex(int index) {
    qualityIndex = index;
  }

  Audio? get audio => qualityIndex == 0 ? lowQualityAudio : highQualityAudio;

   factory HMStreamingData.fromJson(Map<dynamic, dynamic> json) {
    // 🟢 SAFELY CAST THE DYNAMIC MAP TO MAP<STRING, DYNAMIC> 🟢
    final Map<String, dynamic> data = Map<String, dynamic>.from(json);

    return HMStreamingData(
      playable: data['playable'] as bool? ?? false,
      statusMSG: data['statusMSG'] as String? ?? '',
      lowQualityAudio: data['lowQualityAudio'] != null 
          ? Audio.fromJson(Map<String, dynamic>.from(data['lowQualityAudio'])) 
          : null,
      highQualityAudio: data['highQualityAudio'] != null 
          ? Audio.fromJson(Map<String, dynamic>.from(data['highQualityAudio'])) 
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        "playable": playable,
        "statusMSG": statusMSG,
        "lowQualityAudio": lowQualityAudio?.toJson(),
        "highQualityAudio": highQualityAudio?.toJson(),
      };
}
