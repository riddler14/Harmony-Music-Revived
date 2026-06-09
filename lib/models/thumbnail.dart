import 'package:get/get.dart';

class Thumbnail {
  Thumbnail(this._url);
  final String _url;
  
  String sizewith(int size) {
    // 1. Google User Content (Local/YouTube Music Covers)
    if (_url.contains("-rj") || _url.contains("=w")) {
      String base = _url.split("=")[0];
      return "$base=w$size-h$size-l90-rj";
    } 
    // 2. Alternative Google sizing
    else if (_url.contains("=s")) {
      String base = _url.split("=s")[0];
      return "$base=s$size";
    } 
    // 3. YouTube Video Thumbnails (ytimg / i.yti)
    else if (_url.contains("i.yti") || _url.contains("ytimg")) {
      // 🟢 FORCE 1280x720 MAX RESOLUTION 🟢
      return _url
          .replaceAll("default.jpg", "maxresdefault.jpg")
          .replaceAll("mqdefault.jpg", "maxresdefault.jpg")
          .replaceAll("hqdefault.jpg", "maxresdefault.jpg")
          .replaceAll("sddefault.jpg", "maxresdefault.jpg");
    }
    
    return _url;
  }

  String get url => _url;
  
  // Standard sizes for list tiles (fast loading)
  String get high => sizewith(500); 
  String get medium => sizewith(300); 
  String get low => sizewith(150);
  
  // 🟢 CRITICAL FIX FOR HD BACKGROUNDS 🟢
  // Force 1200px+ for extraHigh so backgrounds are crystal clear on mobile!
  String get extraHigh => sizewith(1200); 
}