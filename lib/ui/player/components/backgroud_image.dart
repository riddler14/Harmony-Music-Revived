import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/Settings/settings_screen_controller.dart';
import '../../utils/theme_controller.dart';
import '../player_controller.dart';

class BackgroudImage extends StatelessWidget {
  const BackgroudImage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(
      builder: (playerController) {
        final song = playerController.currentSong.value;
        if (song == null) return const SizedBox.expand();

        final String? artUriStr = song.artUri?.toString();
        final bool isLocalArt = artUriStr != null && artUriStr.startsWith('file:');
        final bool isLegacyOffline = (song.extras?['url'] ?? '').toString().contains('file');

        return SizedBox.expand(
          child: isLocalArt
              ? Builder(builder: (context) {
                  final imgFile = File(Uri.parse(artUriStr).toFilePath());
                  return FutureBuilder(
                    future: imgFile.exists(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          snapshot.hasData &&
                          snapshot.data == true) {
                        if (Get.find<SettingsScreenController>().themeModetype.value == ThemeType.dynamic) {
                          Get.find<ThemeController>().setTheme(FileImage(imgFile), song.id);
                        }
                        return Image.file(
                          imgFile,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high, // 🟢 FORCES HD SCALING
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  );
                })
              : isLegacyOffline
                  ? Builder(builder: (context) {
                      final imgFile = File("${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${song.id}.png");
                      return FutureBuilder(
                        future: imgFile.exists(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.done &&
                              snapshot.hasData &&
                              snapshot.data == true) {
                            if (Get.find<SettingsScreenController>().themeModetype.value == ThemeType.dynamic) {
                              Get.find<ThemeController>().setTheme(FileImage(imgFile), song.id);
                            }
                            return Image.file(
                              imgFile,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high, // 🟢 FORCES HD SCALING
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    })
                  : CachedNetworkImage(
                      imageUrl: artUriStr ?? '',
                      cacheKey: "${song.id}_song",
                      memCacheWidth: null,
                      memCacheHeight: null,
                      // 🟢 REMOVED maxWidthDiskCache/maxHeightDiskCache to save the raw HD file!
                      imageBuilder: (context, imageProvider) {
                        if (Get.find<SettingsScreenController>().themeModetype.value == ThemeType.dynamic) {
                          Future.delayed(
                            const Duration(milliseconds: 50),
                            () => Get.find<ThemeController>().setTheme(imageProvider, song.id),
                          );
                        }
                        return Image(
                          image: imageProvider,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high, // 🟢 FORCES HD SCALING
                        );
                      },
                      errorWidget: (context, url, error) => const SizedBox.shrink(),
                    ),
        );
      },
    );
  }
}