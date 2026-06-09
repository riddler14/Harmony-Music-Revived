import 'dart:async';
import 'dart:io';

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
//import '../models/thumbnail.dart' as th;

class Downloader extends GetxService {
  final _dio = Dio();
  MediaItem? currentSong;
  RxMap<String, List<MediaItem>> playlistQueue =
      <String, List<MediaItem>>{}.obs;
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

    final dirPath =
        Get.find<SettingsScreenController>().downloadLocationPath.string;
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return true;
  }

  Future<void> downloadPlaylist(
      String playlistId, List<MediaItem> songList) async {
    if (!(await checkPermissionNDir())) return;

    // for toggle between downloading request & cancelling
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
    //check if playlist download in queue => download playlistsongs else download from general songs queue
    if (playlistQueue.isNotEmpty) {
      isJobRunning.value = true;
      for (String playlistId in playlistQueue.keys.toList()) {
        //checked in case download cancel request
        if (playlistQueue.containsKey(playlistId)) {
          currentPlaylistId.value = playlistId;
          await downloadSongList((playlistQueue[playlistId]!).toList(),
              isPlaylist: true);
          if (Get.isRegistered<PlaylistScreenController>(
                  tag: Key(playlistId).hashCode.toString()) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<PlaylistScreenController>(
                    tag: Key(playlistId).hashCode.toString())
                .isDownloaded
                .value = true;
          } 
          // in case of album
          else if (Get.isRegistered<AlbumScreenController>(
                  tag: Key(playlistId).hashCode.toString()) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<AlbumScreenController>(
                    tag: Key(playlistId).hashCode.toString())
                .isDownloaded
                .value = true;
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

  Future<void> downloadSongList(List<MediaItem> jobSongList,
      {bool isPlaylist = false}) async {
    for (MediaItem song in jobSongList) {
      // intrrupt downloading task in case of playlist download cancel request
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
      //for playlist downloading counter update
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
    // if (!playerResponse.playable) {
    //   printINFO("Network error! Check your network connection.");
    //   ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
    //       Get.context!, playerResponse.statusMSG,
    //       size: SanckBarSize.BIG,
    //       duration: const Duration(seconds: 2),
    //       top: !GetPlatform.isDesktop));
    //   complete.complete();
    //   return complete.future;
    // }

    if (!playerResponse.playable) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!,
          playerResponse.statusMSG == "networkError"
              ? playerResponse.statusMSG.tr
              : playerResponse.statusMSG,
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
    final actualDownformat =
        requiredAudioStream.audioCodec.name.contains("mp") ? "m4a" : "opus";
    final RegExp invalidChar =
        RegExp(r'Container.|\/|\\|\"|\<|\>|\*|\?|\:|\!|\[|\]|\¡|\||\%');
    final songTitle = "${song.title.trim()} (${song.artist?.trim()})"
        .replaceAll(invalidChar, "");
    String filePath = "$dirPath/$songTitle.$actualDownformat";
    printINFO("Downloading filePath: $filePath");
    final totalBytes = requiredAudioStream.size;

       _dio.download(
        requiredAudioStream.url,
        options: Options(headers: {"Range": 'bytes=0-$totalBytes'}),
        filePath, onReceiveProgress: (count, total) {
      if (total <= 0) return;
      songDownloadingProgress.value = ((count / total) * 100).toInt();
    }).then(
      (value) async {
        // 🟢 WRAP ENTIRE POST-DOWNLOAD IN TRY-CATCH 🟢
        try {
          printINFO(value.data);

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

          // Save Thumbnail
          try {
            final thumbnailPath =
                "${settingsScreenController.supportDirPath}/thumbnails/${song.id}.png";
            if (song.artUri != null) {
              await _dio.downloadUri(song.artUri!, thumbnailPath);
            }
          } catch (e) {}

          // 🟢 SAFE EXTRAS ASSIGNMENT 🟢
                    // 🟢 REMOVE: song.extras ??= {}; (MediaItem is immutable!) 🟢
          
          // 1. Safely update the in-memory extras ONLY if the map already exists
          if (song.extras != null) {
            song.extras!['url'] = filePath;
          }

          // 2. Convert to JSON
          final songJson = MediaItemBuilder.toJson(song);
          
          // 🟢 INJECT THE URL DIRECTLY INTO THE JSON MAP FOR HIVE 🟢
          // This guarantees the downloaded file path is saved to the database!
          songJson['url'] = filePath; 

          final streamInfoJson = requiredAudioStream.toJson();
          streamInfoJson['url'] = filePath;
          songJson["streamInfo"] = [true, streamInfoJson];

          // 3. Save to Hive
          try {
            await Hive.box("SongDownloads").put(song.id, songJson);
            Get.find<LibrarySongsController>().librarySongsList.add(song);
          } catch (hiveError) {
            printERROR("⚠️ [DOWNLOADER] Hive save failed (file is still on disk): $hiveError");
          }
          
          printINFO("Downloaded successfully");

          // 🟢 SAFE TRACK DETAILS PARSING 🟢
                 // 🟢 TRULY SAFE TRACK DETAILS PARSING 🟢
          final trackDetails = (song.extras?['trackDetails'])?.toString().split("/");
          
          final int? trackNumber = (trackDetails != null && trackDetails.isNotEmpty) 
              ? int.tryParse(trackDetails[0]) 
              : null;
              
          final int? totalTracks = (trackDetails != null && trackDetails.length > 1) 
              ? int.tryParse(trackDetails[1]) 
              : null;

                    // 🟢 BULLETPROOF AUDIOTAGS BLOCK (USING DIO & DYNAMIC MIME) 🟢
          try {
            final imageUrl = song.artUri?.toString() ?? "";
            
            if (imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
              // 1. Reliably download image bytes using Dio
              Uint8List? imageBytes;
              try {
                final imgResponse = await _dio.get(
                  imageUrl, 
                  options: Options(responseType: ResponseType.bytes),
                );
                imageBytes = imgResponse.data;
              } catch (imgError) {
                printERROR("⚠️ [DOWNLOADER] Failed to download cover art bytes: $imgError");
              }

              // 2. Dynamic MIME type detection (Defaults to JPEG, checks for PNG)
              final isPng = imageUrl.toLowerCase().endsWith('.png');
              final mimeType = isPng ? MimeType.png : MimeType.jpeg;

              // 3. Build and write the tag
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
                    pictures: [
                      Picture(
                          bytes: imageBytes,
                          mimeType: mimeType,
                          pictureType: PictureType.coverFront)
                    ]);

                await AudioTags.write(filePath, tag);
                printINFO("✅ [DOWNLOADER] AudioTags written successfully!");
                            } else {
                // If image download failed, write tags WITHOUT the picture
                Tag tagNoPic = Tag(
                    title: song.title,
                    trackArtist: song.artist,
                    album: song.album,
                    year: int.tryParse(year ?? ""),
                    trackNumber: trackNumber,
                    trackTotal: totalTracks,
                    albumArtist: song.artist,
                    genre: song.genre,
                    pictures: const []); // 🟢 ADDED EMPTY LIST 🟢
                
              
                await AudioTags.write(filePath, tagNoPic);
                printINFO("✅ [DOWNLOADER] AudioTags written (without cover art)!");
              }
            }
          } catch (e) {
            printERROR("⚠️ [DOWNLOADER] AudioTags final fallback failed: $e");
          }
          
          // 🟢 SHOW SUCCESS SNACKBAR HERE 🟢
          if (Get.context != null) {
            ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                Get.context!, "Song Downloaded".tr,
                size: SanckBarSize.MEDIUM,
                duration: const Duration(seconds: 2),
                top: !GetPlatform.isDesktop));
          }

        } catch (e, stackTrace) {
          // 🟢 CATCHES ANY RANDOM POST-DOWNLOAD CRASH 🟢
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
        // 🟢 THIS NOW ONLY TRIGGERS IF THE ACTUAL NETWORK DOWNLOAD FAILS 🟢
        if (Get.context != null) {
          ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
              Get.context!, "downloadError3".tr,
              size: SanckBarSize.BIG,
              duration: const Duration(seconds: 2),
              top: !GetPlatform.isDesktop));
        }
        printINFO(
            "Downloading failed due to network/stream error! Please try again");
        complete.complete();
      },
    );
    return complete.future;
  }
}
