// ignore_for_file: constant_identifier_names
import 'dart:io'; 
import 'dart:typed_data'; 
import 'package:path_provider/path_provider.dart'; 
import '/ui/screens/Settings/settings_screen_controller.dart'; 
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';
import 'package:dart_ytmusic_api/yt_music.dart';
import '/models/album.dart';
import '/models/artist.dart'; 
import '/services/utils.dart';
import '../utils/helper.dart';
import 'constant.dart';
import 'continuations.dart';
import 'nav_parser.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

enum AudioQuality {
  Low,
  High,
}

class MusicServices extends getx.GetxService {
  final localSongs = getx.RxList<MediaItem>([]);
  final OnAudioQuery _audioQuery = OnAudioQuery();

  final Map<String, String> _headers = {
    'user-agent': userAgent,
    'accept': '*/*',
    'accept-encoding': 'gzip, deflate',
    'content-type': 'application/json',
    'content-encoding': 'gzip',
    'origin': domain,
    'cookie': 'CONSENT=YES+1',
  };

  final Map<String, dynamic> _context = {
    'context': {
      'client': {
        "clientName": "WEB_REMIX",
        "clientVersion": "1.20230213.01.00",
      },
      'user': {}
    }
  };

  @override
  void onInit() {
    init();
    super.onInit();
  }

  final dio = Dio();
  final YTMusic _ytmusic = YTMusic();
  bool _isYTMusicInitialized = false;

  Future<void> _initYTMusic() async {
    if (!_isYTMusicInitialized) {
      await _ytmusic.initialize();
      _isYTMusicInitialized = true;
    }
  }

  // --- SAFE HELPER FUNCTIONS ---
  String _safeStr(dynamic val, [String fallback = 'Unknown']) {
    if (val == null) return fallback;
    return val.toString();
  }

  int _safeDuration(dynamic dur) {
    if (dur == null) return 0;
    if (dur is int) return dur;
    if (dur is String) {
      try {
        final parts = dur.split(':');
        if (parts.length == 2) {
          return int.parse(parts[0]) * 60 + int.parse(parts[1]);
        } else if (parts.length == 3) {
          return int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + int.parse(parts[2]);
        }
      } catch (_) {}
    }
    return 0;
  }

  String? _safeThumbUrl(dynamic thumbnails) {
    try {
      if (thumbnails != null && thumbnails is List && thumbnails.isNotEmpty) {
        return thumbnails.last.url?.toString();
      }
    } catch (_) {}
    return null;
  }

  String _safeArtistNames(dynamic artists) {
    try {
      if (artists != null && artists is List && artists.isNotEmpty) {
        return artists.map((a) => a.name ?? 'Unknown').join(', ');
      }
    } catch (_) {}
    return 'Unknown Artist';
  }
  // -----------------------------

  Future<void> init() async {
    final date = DateTime.now();
    _context['context']['client']['clientVersion'] =
        "1.${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}.01.00";
    final signatureTimestamp = getDatestamp() - 1;
    _context['playbackContext'] = {
      'contentPlaybackContext': {'signatureTimestamp': signatureTimestamp},
    };

    final appPrefsBox = Hive.box('AppPrefs');
    hlCode = appPrefsBox.get('contentLanguage') ?? "en";
    if (appPrefsBox.containsKey('visitorId')) {
      final visitorData = appPrefsBox.get("visitorId");
      if (visitorData != null && !isExpired(epoch: visitorData['exp'])) {
        _headers['X-Goog-Visitor-Id'] = visitorData['id'];
        appPrefsBox.put("visitorId", {
          'id': visitorData['id'],
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2590200
        });
        printINFO("Got Visitor id ($visitorData['id']) from Box");
        return;
      }
    }

    final visitorId = await genrateVisitorId();
    if (visitorId != null) {
      _headers['X-Goog-Visitor-Id'] = visitorId;
      printINFO("New Visitor id generated ($visitorId)");
      appPrefsBox.put("visitorId", {
        'id': visitorId,
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2592000
      });
      return;
    }
    _headers['X-Goog-Visitor-Id'] =
        visitorId ?? "CgttN24wcmd5UzNSWSi2lvq2BjIKCgJKUBIEGgAgYQ%3D%3D";
  }

  set hlCode(String code) {
    _context['context']['client']['hl'] = code;
  }

  Future<String?> genrateVisitorId() async {
    try {
      final response =
          await dio.get(domain, options: Options(headers: _headers));
      final reg = RegExp(r'ytcfg\.set\s*\(\s*({.+?})\s*\)\s*;');
      final matches = reg.firstMatch(response.data.toString());
      String? visitorId;
      if (matches != null) {
        final ytcfg = json.decode(matches.group(1).toString());
        visitorId = ytcfg['VISITOR_DATA']?.toString();
      }
      return visitorId;
    } catch (e) {
      return null;
    }
  }

  Future<Response> _sendRequest(String action, Map<dynamic, dynamic> data,
      {additionalParams = ""}) async {
    try {
      final response =
          await dio.post("$baseUrl$action$fixedParms$additionalParams",
              options: Options(
                headers: _headers,
              ),
              data: data);

      if (response.statusCode == 200) {
        return response;
      } else {
        return _sendRequest(action, data, additionalParams: additionalParams);
      }
    } on DioException catch (e) {
      printINFO("Error $e");
      throw NetworkError();
    }
  }

  Future<dynamic> getHome({int limit = 4}) async {
    await _initYTMusic();
    printINFO("🟢 [HOME] Starting Home Page build...");
    
    final List<Map<String, dynamic>> homeData = [];

    Future<void> buildSection(String searchQuery, String sectionTitle) async {
      try {
        printINFO("🔍 [HOME] Searching for: $searchQuery");
        final results = await search(searchQuery, limit: 15);
        
        final List<dynamic> sectionContents = [];
        
        if (results['Songs'] is List) sectionContents.addAll(results['Songs']);
        if (results['Videos'] is List) sectionContents.addAll(results['Videos']);
        
        printINFO("✅ [HOME] Found ${sectionContents.length} items for '$sectionTitle'");
        
        if (sectionContents.isNotEmpty) {
          homeData.add({
            'title': sectionTitle,
            'contents': sectionContents,
          });
        } else {
          printINFO("⚠️ [HOME] No items found for '$sectionTitle'");
        }
      } catch (e, stacktrace) {
        printINFO("❌ [HOME] Error building '$sectionTitle': $e");
      }
    }

    await buildSection("Pop hits 2024", "Quick picks");
    await buildSection("Chill vibes", "Chill Mix");
    await buildSection("Workout motivation", "Workout Energy");
    await buildSection("Lofi hip hop", "Focus & Study");
    await buildSection("Latest pop music", "New Releases");
    await buildSection("Indie rock", "Indie Mix");

    printINFO("🏁 [HOME] Finished. Total sections to display: ${homeData.length}");
    return homeData;
  }
  Future<List<MediaItem>> scanLocalMusic() async {
    printINFO("🎯 [HYBRID SCAN] Fetching configured download folder...");
    
    List<String> pathsToScan = [];
    
    final appPrefsBox = Hive.box('AppPrefs');
    String? downloadPath = appPrefsBox.get('downloadLocationPath') as String?;
    printINFO("🔍 [DEBUG] Raw Hive path: $downloadPath");

    // 1. Add the user's selected path IF it's a valid raw path (ignore content:// and private app data)
    if (downloadPath != null && downloadPath.isNotEmpty && !downloadPath.contains('/data/user/') && !downloadPath.startsWith('content://')) {
      pathsToScan.add(downloadPath);
    }

    // 2. ALWAYS add standard public folders to guarantee we find the music
    pathsToScan.addAll([
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Downloads',
      '/storage/emulated/0/Harmony_music', // The folder you picked in the logs!
      '/storage/emulated/0/HarmonyMusic',
    ]);

    // Remove duplicates
    pathsToScan = pathsToScan.toSet().toList();
    printINFO("📂 [HYBRID SCAN] Paths to scan: $pathsToScan");

    var status = await Permission.audio.request();
    printINFO("🔑 [DEBUG] Audio permission: $status");
    if (!status.isGranted) {
      status = await Permission.storage.request();
      printINFO("🔑 [DEBUG] Storage permission: $status");
    }
    if (!status.isGranted) {
      printINFO("❌ [HYBRID SCAN] Permissions DENIED! Cannot scan.");
      return [];
    }

    List<MediaItem> foundSongs = [];

    List<SongModel> mediaStoreSongs = [];
    try {
      mediaStoreSongs = await _audioQuery.querySongs();
    } catch (_) {}

    final cacheDir = await getTemporaryDirectory();

    // 3. Loop through ALL possible folders
    for (String path in pathsToScan) {
      final dir = Directory(path);
      if (!await dir.exists()) {
        printINFO("⚠️ [HYBRID SCAN] Directory does not exist: $path");
        continue;
      }

      printINFO("🟢 [HYBRID SCAN] Scanning: $path");
      
      try {
        final entities = dir.listSync(recursive: true, followLinks: false);
        for (var entity in entities) {
          if (entity is File && entity.path.toLowerCase().endsWith('.m4a')) {
            
            // Prevent adding duplicates if paths overlap
            if (foundSongs.any((s) => s.extras?['localPath'] == entity.path)) continue;

            final fileName = entity.path.split('/').last;
            final title = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
            
            Uri? artUri;
            String? localLyrics;

            final lrcPath = entity.path.replaceAll(RegExp(r'\.m4a$', caseSensitive: false), '.lrc');
            if (await File(lrcPath).exists()) {
              try {
                localLyrics = await File(lrcPath).readAsString();
                printINFO("📝 [LYRICS] Found synced .lrc file for: $title");
              } catch (_) {}
            }

            SongModel? matchedSong;
            for (var s in mediaStoreSongs) {
              if (s.data == entity.path || s.uri == entity.path) {
                matchedSong = s;
                break;
              }
            }
            
            if (matchedSong != null) {
              try {
                final Uint8List? artworkBytes = await _audioQuery.queryArtwork(matchedSong.id, ArtworkType.AUDIO);
                if (artworkBytes != null && artworkBytes.isNotEmpty) {
                  final artFile = File('${cacheDir.path}/local_art_${entity.path.hashCode}.jpg');
                  await artFile.writeAsBytes(artworkBytes);
                  artUri = Uri.file(artFile.path);
                  printINFO("🎨 [ARTWORK] Extracted cover art for: $title");
                }
              } catch (_) {}
            }

            foundSongs.add(MediaItem(
              id: "local_${entity.path.hashCode}", 
              title: title,
              artist: matchedSong?.artist ?? "Local Download",
              album: matchedSong?.album ?? "Offline Library",
              artUri: artUri,
              extras: {
                'isLocal': true,
                'localPath': entity.path, 
                'audioQueryId': matchedSong?.id ?? entity.path.hashCode,
                'lyrics': localLyrics,
              },
            ));
          }
        }
      } catch (e) {
        printINFO("❌ [HYBRID SCAN] Error reading folder $path: $e");
      }
    }
    
    printINFO("🏁 [HYBRID SCAN] Finished! Found ${foundSongs.length} downloaded files.");
    return foundSongs;
  }

  Future<List<Map<String, dynamic>>> getCharts(String catogory, {String? countryCode}) async {
    final List<Map<String, dynamic>> charts = [];
    final data = Map.from(_context);

    data['browseId'] = 'FEmusic_charts';
    data['context']['client']["hl"] = 'en';
    if (countryCode != null) {
      data['formData'] = {
        'selectedValues': [countryCode]
      };
    }
    final response = (await _sendRequest('browse', data)).data;
    final results = nav(response, single_column_tab + section_list);
    results.removeAt(0);
    for (dynamic result in results) {
      if (nav(result, [
            "musicCarouselShelfRenderer",
            "header",
            "musicCarouselShelfBasicHeaderRenderer",
            ...title_text
          ]) == "Video charts") {
        for (dynamic item in result['musicCarouselShelfRenderer']['contents']) {
          final chartItem = await getChartItems(parseChartsItemBrowseId(item), catogory);
          charts.add(chartItem);
        }
      } else {
        continue;
      }
    }
    return charts;
  }

  Future<Map<String, dynamic>> getChartItems(Map<String, dynamic> item, String catogory) async {
    final catString = catogory == "TMV" ? "Top Music Videos" : "Trending";
    if ((item['title'])!.contains(catString)) {
      final songs = (await getPlaylistOrAlbumSongs(playlistId: item['browseId']))['tracks'];
      final limitedSongs = songs.length > 24 ? songs.sublist(0, 24) : songs;
      return {'title': item['title'], 'contents': limitedSongs};
    }
    return {'title': item['title'], 'contents': []};
  }

  Future<Map<String, dynamic>> getWatchPlaylist({
    String videoId = "",
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
    String? additionalParamsNext,
    bool onlyRelated = false
  }) async {
    if (videoId.isNotEmpty && videoId.substring(0, 4) == "MPED") {
      videoId = videoId.substring(4);
    }
    final data = Map.from(_context);
    data['enablePersistentPlaylistPanel'] = true;
    data['isAudioOnly'] = true;
    data['tunerSettingValue'] = 'AUTOMIX_SETTING_NORMAL';
    if (videoId == "" && playlistId == null) {
      throw Exception("You must provide either a video id, a playlist id, or both");
    }
    if (videoId != "") {
      data['videoId'] = videoId;
      playlistId ??= "RDAMVM$videoId";

      if (!(radio || shuffle)) {
        data['watchEndpointMusicSupportedConfigs'] = {
          'watchEndpointMusicConfig': {
            'hasPersistentPlaylistPanel': true,
            'musicVideoType': "MUSIC_VIDEO_TYPE_ATV",
          }
        };
      }
    }

    playlistId = validatePlaylistId(playlistId!);
    data['playlistId'] = playlistId;
    final isPlaylist = playlistId.startsWith('PL') || playlistId.startsWith('OLA');
    if (shuffle) data['params'] = "wAEB8gECKAE%3D";
    if (radio) data['params'] = "wAEB";

    final List<dynamic> tracks = [];
    dynamic lyricsBrowseId, relatedBrowseId, playlist;
    final results = {};

    if (additionalParamsNext == null) {
      final response = (await _sendRequest("next", data)).data;
      final watchNextRenderer = nav(response, [
        'contents', 'singleColumnMusicWatchNextResultsRenderer', 'tabbedRenderer', 'watchNextTabbedResultsRenderer'
      ]);

      lyricsBrowseId = getTabBrowseId(watchNextRenderer, 1);
      relatedBrowseId = getTabBrowseId(watchNextRenderer, 2);
      if (onlyRelated) {
        return {'lyrics': lyricsBrowseId, 'related': relatedBrowseId};
      }

      results.addAll(nav(watchNextRenderer, [...tab_content, 'musicQueueRenderer', 'content', 'playlistPanelRenderer']));
      playlist = results['contents']
          .map((content) => nav(content, ['playlistPanelVideoRenderer', ...navigation_playlist_id]))
          .where((e) => e != null).toList().first;
      tracks.addAll(parseWatchPlaylist(results['contents']));
    }

    dynamic additionalParamsForNext;
    if (results.containsKey('continuations') || additionalParamsNext != null) {
      requestFunc(additionalParams) async => (await _sendRequest("next", data, additionalParams: additionalParams)).data;
      parseFunc(contents) => parseWatchPlaylist(contents);
      final x = await getContinuations(results, 'playlistPanelContinuation', limit - tracks.length, requestFunc, parseFunc,
          ctokenPath: isPlaylist ? '' : 'Radio', isAdditionparamReturnReq: true, additionalParams_: additionalParamsNext);
      additionalParamsForNext = x[1];
      tracks.addAll(List<dynamic>.from(x[0]));
    }

    return {
      'tracks': tracks, 'playlistId': playlist, 'lyrics': lyricsBrowseId,
      'related': relatedBrowseId, 'additionalParamsForNext': additionalParamsForNext
    };
  }

  Future<String> getAlbumBrowseId(String audioPlaylistId) async {
    final response = await dio.get("${domain}playlist", options: Options(headers: _headers), queryParameters: {"list": audioPlaylistId});
    final reg = RegExp(r'\"MPRE.+?\"');
    final matchs = reg.firstMatch(response.data.toString());
    if (matchs != null) {
      final x = (matchs[0])!;
      final res = (x.substring(1)).split("\\")[0];
      return res;
    }
    return audioPlaylistId;
  }

  dynamic getContentRelatedToSong(String videoId, String hlCode) async {
    final params = await getWatchPlaylist(videoId: videoId, onlyRelated: true);
    final data = Map.from(_context);
    data['browseId'] = params['related'];
    data['context']['client']['hl'] = hlCode;
    final response = (await _sendRequest('browse', data)).data;
    final sections = nav(response, ['contents'] + section_list);
    return parseMixedContent(sections);
  }

  dynamic getLyrics(String browseId) async {
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final response = (await _sendRequest('browse', data)).data;
    return nav(response, ['contents', ...section_list_item, ...description_shelf, ...description]);
  }

  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs({
    String? playlistId, String? albumId, int limit = 3000, bool related = false, int suggestionsLimit = 0
  }) async {
    String browseId = playlistId != null ? (playlistId.startsWith("VL") ? playlistId : "VL$playlistId") : albumId!;
    if (albumId != null && albumId.contains("OLAK5uy")) browseId = await getAlbumBrowseId(browseId);
    
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final Map<String, dynamic> response = (await _sendRequest('browse', data)).data;
    
    if (playlistId != null) {
      final Map<String, dynamic> header = nav(response, ['header', "musicDetailHeaderRenderer"]) ??
          nav(response, ['contents', "twoColumnBrowseResultsRenderer", 'tabs', 0, "tabRenderer", "content", 'sectionListRenderer', 'contents', 0, "musicResponsiveHeaderRenderer"]);

      final Map<String, dynamic> results = nav(response, musicPlaylistShelfRenderer) ??
          nav(response, ['contents', "singleColumnBrowseResultsRenderer", 'tabs', 0, "tabRenderer", "content", 'sectionListRenderer', 'contents', 0, "musicPlaylistShelfRenderer"]);
      
      final Map<String, dynamic> playlist = {'id': results['playlistId']};
      playlist['title'] = nav(header, title_text);
      playlist['thumbnails'] = nav(header, thumnail_cropped) ?? nav(header, ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]);
      playlist["description"] = nav(header, description);
      
      final int runCount = header['subtitle']['runs'].length;
      if (runCount > 1) {
        playlist['author'] = {'name': nav(header, subtitle2), 'id': nav(header, ['subtitle', 'runs', 2] + navigation_browse_id)};
        if (runCount == 5) playlist['year'] = nav(header, subtitle3);
      }

      final int secondSubtitleRunCount = header['secondSubtitle']['runs'].length;
      final String count = (((header['secondSubtitle']['runs'][secondSubtitleRunCount % 3]['text']).split(' ')[0]).split(',') as List).join();
      final int songCount = int.parse(count);
      if (header['secondSubtitle']['runs'].length > 1) {
        playlist['duration'] = header['secondSubtitle']['runs'][(secondSubtitleRunCount % 3) + 2]['text'];
      }
      playlist['trackCount'] = songCount;

      requestFuncCountinuation(cont) async => (await _sendRequest("browse", {...data, ...cont})).data;

      if (songCount > 0) {
        playlist['tracks'] = parsePlaylistItems(results['contents']);
        limit = songCount;
        List<dynamic> parseFunc(contents) => parsePlaylistItems(contents);
        playlist['tracks'] = [...(playlist['tracks']), ...(await getContinuationsPlaylist(results, limit, requestFuncCountinuation, parseFunc))];
      }
      playlist['duration_seconds'] = sumTotalDuration(playlist);
      return playlist;
    }

    final album = parseAlbumHeader(response);
    dynamic results = nav(response, ['contents', "twoColumnBrowseResultsRenderer", "secondaryContents", 'sectionListRenderer', 'contents', 0, 'musicShelfRenderer']) ??
        nav(response, ['contents', "singleColumnBrowseResultsRenderer", 'tabs', 0, "tabRenderer", "content", 'sectionListRenderer', 'contents', 0, 'musicShelfRenderer']);

    album['tracks'] = parsePlaylistItems(results['contents'], artistsM: album['artists'], thumbnailsM: album["thumbnails"], albumIdName: {"id": albumId, 'name': album['title']}, albumYear: album['year'], isAlbum: true);
    results = nav(response, [...single_column_tab, ...section_list, 1, 'musicCarouselShelfRenderer']);
    
    if (results != null) {
      List contents = [];
      if (results.runtimeType.toString().contains("Iterable") || results.runtimeType.toString().contains("List")) {
        for (dynamic result in results) contents.add(parseAlbum(result['musicTwoRowItemRenderer']));
      } else {
        contents.add(parseAlbum(results['contents'][0]['musicTwoRowItemRenderer']));
      }
      album['other_versions'] = contents;
    }
    album['duration_seconds'] = sumTotalDuration(album);
    return album;
  }

  Future<List<String>> getSearchSuggestion(String queryStr) async {
    await _initYTMusic();
    try {
      final suggestions = await _ytmusic.getSearchSuggestions(queryStr);
      if (suggestions == null) return [];
      return suggestions.map((s) => s.toString()).toList();
    } catch (e) {
      printINFO("Search suggestion error: $e");
      return [];
    }
  }

  Future<List> getSongWithId(String songId) async {
    final data = Map.of(_context);
    data['videoId'] = songId;
    final response = (await _sendRequest("player", data)).data;
    final category = nav(response, ["microformat", "microformatDataRenderer", "category"]);
    if (category == "Music" || (response["videoDetails"]).containsKey("musicVideoType")) {
      final list = await getWatchPlaylist(videoId: songId);
      return [true, list['tracks']];
    }
    return [false, null];
  }

  String _formatTime(int seconds) {
    if (seconds <= 0) return "";
    int minutes = seconds ~/ 60;
    int secs = seconds % 60;
    return "$minutes:${secs.toString().padLeft(2, '0')}";
  }

    Future<Map<String, dynamic>> search(String query, {String? filter, String? scope, int limit = 30, bool ignoreSpelling = false, String? filterParams}) async {
    await _initYTMusic();
    
    final Map<String, dynamic> searchResults = {
      'Songs': [], 'Videos': [], 'Artists': [], 'Albums': [],
      'Playlists': [], 'Featured playlists': [], 'Community playlists': [], 'searchEndpoint': {},
    };

    // 🟢 BULLETPROOF FALLBACK IMAGE 🟢
    // If YouTube fails to give us a thumbnail, we use this placeholder so the UI image loader NEVER crashes.
    final String placeholderImg = 'https://via.placeholder.com/150/000000/FFFFFF/?text=Music';

    try {
      // 1. SONGS
      if (filter == null || filter == 'songs') {
        try {
          final songs = await _ytmusic.searchSongs(query);
          final validSongs = songs.where((s) => (s.videoId ?? '').isNotEmpty).take(limit);
          searchResults['Songs'] = validSongs.map((song) {
            String thumbUrl = placeholderImg;
            try {
              if (song.thumbnails != null && song.thumbnails!.isNotEmpty && song.thumbnails!.last.url != null) {
                thumbUrl = song.thumbnails!.last.url!;
              }
            } catch (_) {}
            
            final int durSeconds = song.duration ?? 0;
            return MediaItem(
              id: song.videoId ?? '', 
              title: song.name ?? 'Unknown Title', 
              artist: song.artist?.name ?? 'Unknown Artist',
              album: song.album?.name ?? 'Unknown Album', 
              artUri: Uri.tryParse(thumbUrl), 
              duration: Duration(seconds: durSeconds),
              extras: {'length': _formatTime(durSeconds)}, 
            );
          }).toList();
        } catch (e) { printINFO("Songs error: $e"); }
      }

      // 2. VIDEOS
      if (filter == null || filter == 'videos') {
        try {
          final videos = await _ytmusic.searchVideos(query);
          final validVideos = videos.where((v) => (v.videoId ?? '').isNotEmpty).take(limit);
          searchResults['Videos'] = validVideos.map((video) {
            String thumbUrl = placeholderImg;
            try {
              if (video.thumbnails != null && video.thumbnails!.isNotEmpty && video.thumbnails!.last.url != null) {
                thumbUrl = video.thumbnails!.last.url!;
              }
            } catch (_) {}
            
            final int durSeconds = video.duration ?? 0;
            return MediaItem(
              id: video.videoId ?? '', 
              title: video.name ?? 'Unknown Title', 
              artist: video.artist?.name ?? 'Unknown Artist', 
              artUri: Uri.tryParse(thumbUrl), 
              duration: Duration(seconds: durSeconds),
              extras: {'length': _formatTime(durSeconds)}, 
            );
          }).toList();
        } catch (e) { printINFO("Videos error: $e"); }
      }

      // 3. ARTISTS
      if (filter == null || filter == 'artists') {
        try {
          final ytArtists = await _ytmusic.searchArtists(query);
          searchResults['Artists'] = ytArtists.where((a) => (a.artistId ?? '').isNotEmpty).take(limit).map((ytArtist) {
            String thumbUrl = placeholderImg;
            try {
              if (ytArtist.thumbnails != null && ytArtist.thumbnails!.isNotEmpty && ytArtist.thumbnails!.last.url != null) {
                thumbUrl = ytArtist.thumbnails!.last.url!;
              }
            } catch (_) {}
            
            return Artist(
              name: ytArtist.name ?? 'Unknown Artist',
              browseId: ytArtist.artistId!,
              thumbnailUrl: thumbUrl,
              // 🟢 FORCE EMPTY STRINGS FOR OPTIONAL FIELDS 🟢
              // This prevents the UI from crashing if it tries to read these as Strings!
              radioId: '',
              subscribers: '',
            );
          }).toList();
        } catch (e) { printINFO("Artists error: $e"); }
      }

      // 4. ALBUMS
      if (filter == null || filter == 'albums') {
        try {
          final albums = await _ytmusic.searchAlbums(query);
          searchResults['Albums'] = albums.where((a) => (a.albumId ?? '').isNotEmpty).take(limit).map((album) {
            String thumbUrl = placeholderImg;
            try {
              if (album.thumbnails != null && album.thumbnails!.isNotEmpty && album.thumbnails!.last.url != null) {
                thumbUrl = album.thumbnails!.last.url!;
              }
            } catch (_) {}
            
            return Album(
              title: album.name ?? 'Unknown Album', 
              browseId: album.albumId ?? '', 
              audioPlaylistId: album.playlistId ?? '', 
              artists: [ {'name': album.artist?.name ?? 'Unknown Artist'} ], 
              year: album.year?.toString() ?? 'Unknown Year', 
              thumbnailUrl: thumbUrl,
            );
          }).toList();
        } catch (e) { printINFO("Albums error: $e"); }
      }

      // 5. PLAYLISTS
      if (filter == null || filter == 'playlists' || filter == 'community_playlists' || filter == 'featured_playlists') {
        try {
          final playlists = await _ytmusic.searchPlaylists(query);
          searchResults['Playlists'] = playlists.where((p) => (p.playlistId ?? '').isNotEmpty).take(limit).map((playlist) {
            String thumbUrl = placeholderImg;
            try {
              if (playlist.thumbnails != null && playlist.thumbnails!.isNotEmpty && playlist.thumbnails!.last.url != null) {
                thumbUrl = playlist.thumbnails!.last.url!;
              }
            } catch (_) {}
            
            return Album(
              title: playlist.name ?? 'Unknown Playlist', 
              browseId: playlist.playlistId ?? '', 
              audioPlaylistId: playlist.playlistId ?? '', 
              artists: [ {'name': playlist.artist?.name ?? 'Unknown Artist'} ], 
              year: '', 
              thumbnailUrl: thumbUrl,
            );
          }).toList();
          
          if (filter == null) {
            searchResults['Community playlists'] = searchResults['Playlists'];
            searchResults['Featured playlists'] = searchResults['Playlists'];
          }
        } catch (e) { printINFO("Playlists error: $e"); }
      }
    } catch (e, stacktrace) {
      printINFO("General search error: $e\n$stacktrace");
    }
    
    return searchResults;
  }

  Future<Map<String, dynamic>> getSearchContinuation(Map additionalParamsNext, {int limit = 10}) async {
    return {"params": additionalParamsNext, "data": []};
  }

  Future<Map<String, dynamic>> getArtist(String channelId) async {
    if (channelId.startsWith("MPLA")) channelId = channelId.substring(4);
    final data = Map.from(_context);
    data['context']['client']["hl"] = 'en';
    data['browseId'] = channelId;
    final response = (await _sendRequest("browse", data)).data;
    final results = nav(response, [...single_column_tab, ...section_list]);

    final Map<String, dynamic> artist = {'description': null, 'views': null};
    final Map<String, dynamic> header = (response['header']['musicImmersiveHeaderRenderer']) ?? response['header']['musicVisualHeaderRenderer'];
    artist['name'] = nav(header, title_text);
    final descriptionShelf = findObjectByKey(results, description_shelf[0], isKey: true);
    if (descriptionShelf != null) {
      artist['description'] = nav(descriptionShelf, description);
      artist['views'] = descriptionShelf['subheader'] == null ? null : descriptionShelf['subheader']['runs'][0]['text'];
    }
    final dynamic subscriptionButton = header['subscriptionButton'] != null ? header['subscriptionButton']['subscribeButtonRenderer'] : null;
    artist['channelId'] = channelId;
    artist['shuffleId'] = nav(header, ['playButton', 'buttonRenderer', ...navigation_watch_playlist_id]);
    artist['radioId'] = nav(header, ['startRadioButton', 'buttonRenderer'] + navigation_playlist_id);
    artist['subscribers'] = subscriptionButton != null ? nav(subscriptionButton, ['subscriberCountText', 'runs', 0, 'text']) : null;
    artist['thumbnails'] = nav(header, thumbnails);
    artist.addAll(parseArtistContents(results));
    return artist;
  }

  Future<Map<String, dynamic>> getArtistRealtedContent(Map<String, dynamic> browseEndpoint, String category, {String additionalParams = ""}) async {
    final Map<String, dynamic> result = {"results": []};
    final data = Map.of(_context);
    browseEndpoint.remove("content");
    if (browseEndpoint.isEmpty) return result;
    data.addAll(browseEndpoint);
    final response = (await _sendRequest("browse", data, additionalParams: additionalParams)).data;
    final contents = nav(response, ['contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0, "tabRenderer", "content", 'sectionListRenderer', 'contents', 0]);

    if (category == "Songs" || category == "Videos") {
      if (additionalParams != "") {
        final contentList = nav(response, ["onResponseReceivedActions", 0, "appendContinuationItemsAction", "continuationItems"]);
        result['results'] = parsePlaylistItems(contentList);
        result['additionalParams'] = "&ctoken=${null}&continuation=${null}";
      } else if (contents.containsKey("gridRenderer")) {
        result['results'] = (contents['gridRenderer']['items']).map((video) => parseVideo(video['musicTwoRowItemRenderer'])).toList();
        result['additionalParams'] = "&ctoken=${null}&continuation=${null}";
      } else {
        final collapseContent = nav(contents, ['musicPlaylistShelfRenderer', "collapsedItemCount"]);
        if (collapseContent != null) {
          final contentlist = contents['musicPlaylistShelfRenderer']['contents'];
          if (contentlist.length.toString() != collapseContent.toString()) {
            final continuationItem = contentlist.removeAt(100);
            result['results'] = parsePlaylistItems(contentlist);
            final continuationKey = nav(continuationItem, ["continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token"]);
            result['additionalParams'] = "&ctoken=$continuationKey&continuation=$continuationKey";
          } else {
            result['results'] = parsePlaylistItems(contentlist);
            result['additionalParams'] = "&ctoken=null&continuation=null";
          }
        }
        return result;
      }
    } else if (category == 'Albums' || category == 'Singles') {
      List contentlist;
      if (additionalParams != "") {
        contentlist = response['continuationContents']['gridContinuation']['items'];
        final continuationKey = nav(response, ['continuationContents', 'gridContinuation', 'continuations', 0, 'nextContinuationData', 'continuation']);
        result['additionalParams'] = "&ctoken=$continuationKey&continuation=$continuationKey";
      } else {
        contentlist = contents['gridRenderer']['items'];
        final continuationKey = nav(contents, ['gridRenderer', 'continuations', 0, 'nextContinuationData', 'continuation']);
        result['additionalParams'] = "&ctoken=$continuationKey&continuation=$continuationKey";
      }
      result['results'] = category == 'Albums' ? contentlist.map((item) => parseAlbum(item['musicTwoRowItemRenderer'])).whereType<Album>().toList() : contentlist.map((item) => parseSingle(item['musicTwoRowItemRenderer'])).whereType<Album>().toList();
    }
    return result;
  }

  Future<String?> getSongYear(String songId) async {
    final data = Map.from(_context);
    data['browseId'] = "MPTC$songId";
    try {
      final response = (await _sendRequest('browse', data)).data;
      String? year = nav(response, ["onResponseReceivedActions", 0, "openPopupAction", "popup", "dismissableDialogRenderer", "metadata", "musicMultiRowListItemRenderer", "secondTitle", "runs", 2, "text"]);
      return year;
    } catch (e) {
      rethrow;
    }
  }

  @override
  void onClose() {
    dio.close();
    super.onClose();
  }
}

class NetworkError extends Error {
  final message = "Network Error !";
}