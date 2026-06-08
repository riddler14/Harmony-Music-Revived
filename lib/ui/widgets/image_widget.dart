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
    String imageUrl = "";
    if (song != null) {
      imageUrl = song!.artUri?.toString() ?? "";
    } else if (playlist != null) {
      imageUrl = playlist!.thumbnailUrl ?? "";
    } else if (album != null) {
      imageUrl = album!.thumbnailUrl ?? "";
    } else if (artist != null) {
      imageUrl = artist!.thumbnailUrl ?? "";
    }

    // 🟢 BULLETPROOF CHECK: Prevent "null" strings or empty paths from crashing CachedNetworkImage 🟢
    if (imageUrl.isEmpty || imageUrl == "null" || imageUrl == "[]") {
      return _buildErrorWidget(context);
    }

    final bool offlineAvailable =
        song != null && (song?.extras?["url"] ?? "").toString().contains("file");

    final bool isLocalArtFile = imageUrl.startsWith('file:');

    Widget errorWidget() => _buildErrorWidget(context);

    return Container(
      height: size,
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: artist != null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: artist != null ? null : BorderRadius.circular(5),
      ),
      child: isLocalArtFile
          ? Builder(builder: (context) {
              // 🟢 SAFE FILE PARSING: Catches malformed file:// paths on HyperOS 🟢
              try {
                return Image.file(
                  File(Uri.parse(imageUrl).toFilePath()),
                  height: size,
                  width: size,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => errorWidget(),
                );
              } catch (e) {
                return errorWidget();
              }
            })
          : offlineAvailable
              ? Image.file(
                  File("${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${song!.id}.png"),
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
                          shape: artist != null ? BoxShape.circle : BoxShape.rectangle,
                          borderRadius: artist != null ? null : BorderRadius.circular(10),
                          color: Colors.white54,
                        ),
                      ))),
                ),
    );
  }

  Widget _buildErrorWidget(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        shape: artist != null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: artist != null ? null : BorderRadius.circular(10),
      ),
      child: Image.asset(
        "assets/icons/${song != null ? "song" : artist != null ? "artist" : "album"}.png",
        errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white54),
      ),
    );
  }
}