import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';

import '../screens/Settings/settings_screen_controller.dart';
import '/models/artist.dart';
import '../../models/album.dart';
import '../../models/playlist.dart';

class ImageWidget extends StatelessWidget {
  const ImageWidget({
    super.key,
    this.song,
    this.playlist,
    this.album,
    this.artist,
    required this.size,
    this.isPlayerArtImage = false,
  });
  final MediaItem? song;
  final Playlist? playlist;
  final Album? album;
  final bool isPlayerArtImage;
  final Artist? artist;
  final double size;

   @override
  Widget build(BuildContext context) {
    String imageUrl = song != null
        ? (song!.artUri?.toString() ?? "")
        : playlist != null
            ? playlist!.thumbnailUrl
            : album != null
                ? album!.thumbnailUrl
                : artist != null
                    ? artist!.thumbnailUrl
                    : "";

    /// only valid for offline songs (Original app downloads)
    final bool offlineAvailable =
        song != null && (song?.extras?["url"] ?? "").toString().contains("file");

    // 🟢 NEW: Check if the artUri itself is a local file (from our Hybrid Scanner) 🟢
    final bool isLocalArtFile = imageUrl.startsWith('file:');

    // Helper widget for errors to keep the code clean
    Widget errorWidget() {
      return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            shape: artist != null ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: artist != null ? null : BorderRadius.circular(10),
          ),
          child: Image.asset(
              "assets/icons/${song != null ? "song" : artist != null ? "artist" : "album"}.png"));
    }

    return Container(
      height: size,
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: artist != null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: artist != null ? null : BorderRadius.circular(5),
      ),
      child: isLocalArtFile
          ? Image.file(
              File(Uri.parse(imageUrl).toFilePath()),
              height: size,
              width: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => errorWidget(),
            )
          : offlineAvailable
              ? Image.file(
                  File(
                      "${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${song!.id}.png"),
                  height: size,
                  width: size,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => errorWidget(),
                )
              : CachedNetworkImage(
                  height: size,
                  width: size,
                  memCacheHeight: (song != null && !isPlayerArtImage) ? 140 : null,
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => errorWidget(),
                  progressIndicatorBuilder: ((_, __, ___) => Shimmer.fromColors(
                      baseColor: Colors.grey[500]!,
                      highlightColor: Colors.grey[300]!,
                      enabled: true,
                      direction: ShimmerDirection.ltr,
                      child: Container(
                        decoration: BoxDecoration(
                          shape:
                              artist != null ? BoxShape.circle : BoxShape.rectangle,
                          borderRadius:
                              artist != null ? null : BorderRadius.circular(10),
                          color: Colors.white54,
                        ),
                      ))),
                ),
    );
  }
}
