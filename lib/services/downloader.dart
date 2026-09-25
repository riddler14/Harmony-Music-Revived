import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:audiotags/audiotags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../ui/screens/Album/album_screen_controller.dart';
import '../ui/screens/Playlist/playlist_screen_controller.dart';
import '/services/stream_service.dart';
import '../ui/widgets/snackbar.dart';
import '/services/permission_service.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '/models/media_Item_builder.dart';
import '../ui/screens/Library/library_controller.dart';
import 'music_service.dart';

class Downloader extends GetxService {
  final _dio = Dio();
  MediaItem? currentSong;
  RxMap<String, List<MediaItem>> playlistQueue = <String, List<MediaItem>>{}.obs;
  final currentPlaylistId = "".obs;
  final songDownloadingProgress = 0.obs;
  final playlistDownloadingProgress = 0.obs;
  final isJobRunning = false.obs;

  RxList<MediaItem> songQueue = <MediaItem>[].obs;

  Future<bool> checkPermissionNDir() async {
    final settingsScreenController = Get.find<SettingsScreenController>();

    if (!settingsScreenController.isCurrentPathsupportDownDir &&
        !await PermissionService.getExtStoragePermission()) {
      return false;
    }

    final dirPath = Get.find<SettingsScreenController>().downloadLocationPath.string;
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return true;
  }

  Future<void> downloadPlaylist(String playlistId, List<MediaItem> songList) async {
    if (!(await checkPermissionNDir())) return;

    if (playlistQueue.containsKey(playlistId)) {
      songQueue.removeWhere((element) => songList.contains(element));
      playlistQueue.remove(playlistId);
      return;
    }

    playlistQueue[playlistId] = songList;
    songQueue.addAll(songList);

    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  Future<void> download(MediaItem? song, {List<MediaItem>? songList}) async {
    if (!(await checkPermissionNDir())) return;
    if (songList != null) {
      songQueue.addAll(songList);
    } else {
      songQueue.add(song!);
    }
    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  Future<void> triggerDownloadingJob() async {
    if (playlistQueue.isNotEmpty) {
      isJobRunning.value = true;
      for (String playlistId in playlistQueue.keys.toList()) {
        if (playlistQueue.containsKey(playlistId)) {
          currentPlaylistId.value = playlistId;
          await downloadSongList((playlistQueue[playlistId]!).toList(), isPlaylist: true);
          if (Get.isRegistered<PlaylistScreenController>(tag: Key(playlistId).hashCode.toString()) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<PlaylistScreenController>(tag: Key(playlistId).hashCode.toString()).isDownloaded.value = true;
          } else if (Get.isRegistered<AlbumScreenController>(tag: Key(playlistId).hashCode.toString()) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<AlbumScreenController>(tag: Key(playlistId).hashCode.toString()).isDownloaded.value = true;
          }
          playlistQueue.remove(playlistId);
        }
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
      }
    } else {
      isJobRunning.value = true;
      await downloadSongList(songQueue.toList());
    }

    if (songQueue.isNotEmpty) {
      triggerDownloadingJob();
    } else {
      isJobRunning.value = false;
      currentSong = null;
    }
  }

  Future<void> downloadSongList(List<MediaItem> jobSongList, {bool isPlaylist = false}) async {
    for (MediaItem song in jobSongList) {
      if (isPlaylist && !playlistQueue.containsKey(currentPlaylistId.value)) {
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
        return;
      }

      if (!Hive.box("SongDownloads").containsKey(song.id)) {
        currentSong = song;
        songDownloadingProgress.value = 0;
        await writeFileStream(song);
      }
      songQueue.remove(song);
      if (isPlaylist) {
        playlistDownloadingProgress.value = jobSongList.indexOf(song) + 1;
      }
    }
  }

  Future<void> writeFileStream(MediaItem song) async {
    Completer<void> complete = Completer();

    final settingsScreenController = Get.find<SettingsScreenController>();
    final downloadingFormat = settingsScreenController.downloadingFormat.string;

    final playerResponse = await StreamProvider.fetch(song.id);

    if (!playerResponse.playable) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!,
          playerResponse.statusMSG == "networkError" ? playerResponse.statusMSG.tr : playerResponse.statusMSG,
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 2),
          top: !GetPlatform.isDesktop));
      printINFO("Requested song is not downloadable. You may try again");
      complete.complete();
      return complete.future;
    }

    Audio requiredAudioStream = downloadingFormat == "opus"
        ? playerResponse.highestBitrateOpusAudio!
        : playerResponse.highestBitrateMp4aAudio!;

    final dirPath = settingsScreenController.downloadLocationPath.string;
    final actualDownformat = requiredAudioStream.audioCodec.name.contains("mp") ? "m4a" : "opus";
    final RegExp invalidChar = RegExp(r'Container.|\/|\\|\"|\<|\>|\*|\?|\:|\!|\[|\]|\¡|\||\%');
    final songTitle = "${song.title.trim()} (${song.artist?.trim()})".replaceAll(invalidChar, "");
    String filePath = "$dirPath/$songTitle.$actualDownformat";
    printINFO("Downloading filePath: $filePath");
    final totalBytes = requiredAudioStream.size;

    // 🟢 THE FIX: Add the User-Agent headers to bypass the 403 Forbidden on download! 🟢
    _dio.download(
      requiredAudioStream.url,
      filePath,
      options: Options(
        headers: {
          "Range": 'bytes=0-$totalBytes',
          "User-Agent": requiredAudioStream.userAgent, // 🟢 THE SECRET PASSWORD
          "Referer": "https://www.youtube.com/",
          "Origin": "https://www.youtube.com",
          "Accept": "*/*",
        },
      ),
      onReceiveProgress: (count, total) {
        if (total <= 0) return;
        songDownloadingProgress.value = ((count / total) * 100).toInt();
      },
    ).then(
      (value) async {
        try {
          String? year;
          try {
            if (song.extras?['year'] != null) {
              year = song.extras?['year'];
            } else {
              if (song.album != null) {
                final musicServ = Get.find<MusicServices>();
                year = await musicServ.getSongYear(song.id);
              }
            }
          } catch (_) {}

          try {
            final thumbnailPath = "${settingsScreenController.supportDirPath}/thumbnails/${song.id}.png";
            if (song.artUri != null) {
              await _dio.downloadUri(song.artUri!, thumbnailPath);
            }
          } catch (e) {
            // Thumbnail download failures should not interrupt the song download.
          }

          if (song.extras != null) {
            song.extras!['url'] = filePath;
          }

          final songJson = MediaItemBuilder.toJson(song);
          songJson['url'] = filePath; 

          final streamInfoJson = requiredAudioStream.toJson();
          streamInfoJson['url'] = filePath;
          songJson["streamInfo"] = [true, streamInfoJson];

          try {
            await Hive.box("SongDownloads").put(song.id, songJson);
            Get.find<LibrarySongsController>().librarySongsList.add(song);
          } catch (hiveError) {
            printERROR("⚠️ [DOWNLOADER] Hive save failed (file is still on disk): $hiveError");
          }
          
          printINFO("Downloaded successfully");

          final trackDetails = (song.extras?['trackDetails'])?.toString().split("/");
          final int? trackNumber = (trackDetails != null && trackDetails.isNotEmpty) ? int.tryParse(trackDetails[0]) : null;
          final int? totalTracks = (trackDetails != null && trackDetails.length > 1) ? int.tryParse(trackDetails[1]) : null;

          try {
            final imageUrl = song.artUri?.toString() ?? "";
            
            if (imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
              Uint8List? imageBytes;
              try {
                final imgResponse = await _dio.get(imageUrl, options: Options(responseType: ResponseType.bytes));
                imageBytes = imgResponse.data;
              } catch (imgError) {
                printERROR("⚠️ [DOWNLOADER] Failed to download cover art bytes: $imgError");
              }

              final isPng = imageUrl.toLowerCase().endsWith('.png');
              final mimeType = isPng ? MimeType.png : MimeType.jpeg;

              if (imageBytes != null) {
                Tag tag = Tag(
                    title: song.title,
                    trackArtist: song.artist,
                    album: song.album,
                    year: int.tryParse(year ?? ""),
                    trackNumber: trackNumber,
                    trackTotal: totalTracks,
                    albumArtist: song.artist,
                    genre: song.genre,
                    pictures: [Picture(bytes: imageBytes, mimeType: mimeType, pictureType: PictureType.coverFront)]);

                await AudioTags.write(filePath, tag);
                printINFO("✅ [DOWNLOADER] AudioTags written successfully!");
              } else {
                Tag tagNoPic = Tag(
                    title: song.title,
                    trackArtist: song.artist,
                    album: song.album,
                    year: int.tryParse(year ?? ""),
                    trackNumber: trackNumber,
                    trackTotal: totalTracks,
                    albumArtist: song.artist,
                    genre: song.genre,
                    pictures: const []);
                
                await AudioTags.write(filePath, tagNoPic);
                printINFO("✅ [DOWNLOADER] AudioTags written (without cover art)!");
              }
            }
          } catch (e) {
            printERROR("⚠️ [DOWNLOADER] AudioTags final fallback failed: $e");
          }
          
          if (Get.context != null) {
            ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                Get.context!, "Song Downloaded".tr,
                size: SanckBarSize.MEDIUM,
                duration: const Duration(seconds: 2),
                top: !GetPlatform.isDesktop));
          }

        } catch (e, stackTrace) {
          printERROR("⚠️ [DOWNLOADER] Post-download processing failed: $e");
          printERROR(stackTrace);
          if (Get.context != null) {
            ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                Get.context!, "File saved, but metadata tagging failed.",
                size: SanckBarSize.MEDIUM,
                duration: const Duration(seconds: 2),
                top: !GetPlatform.isDesktop));
          }
        } finally {
          complete.complete();
        }
      },
    ).onError(
      (error, stackTrace) {
        if (Get.context != null) {
          ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
              Get.context!, "downloadError3".tr,
              size: SanckBarSize.BIG,
              duration: const Duration(seconds: 2),
              top: !GetPlatform.isDesktop));
        }
        printINFO("Downloading failed due to network/stream error! Please try again");
        complete.complete();
      },
    );
    return complete.future;
  }
}