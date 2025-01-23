import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadService {
  static final Dio _dio = Dio();
  
  static Future<String?> downloadUpdate(String url, void Function(int, int)? onProgress) async {
    try {
      // Solicita permissão de armazenamento
      if (!await _requestStoragePermission()) {
        debugPrint('Permissão de armazenamento negada');
        return null;
      }

      // Define o diretório de download
      final downloadPath = await _getDownloadPath();
      if (downloadPath == null) {
        debugPrint('Caminho de download não encontrado');
        return null;
      }

      // Define o nome do arquivo
      final fileName = 'app-update.apk';
      final savePath = '$downloadPath/$fileName';

      // Remove arquivo anterior se existir
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      // Faz o download
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
        options: Options(
          followRedirects: true,
          responseType: ResponseType.bytes,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (await file.exists()) {
        return savePath;
      }
      return null;
    } catch (e) {
      debugPrint('Erro no download: $e');
      return null;
    }
  }

  static Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Verifica a versão do Android
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) { // Android 13 ou superior
        final status = await Permission.photos.request();
        if (status.isGranted) {
          return true;
        }
        
        // Se negado, tenta permissão de mídia
        final mediaStatus = await Permission.mediaLibrary.request();
        return mediaStatus.isGranted;
      } else {
        // Android 12 ou inferior
        final status = await Permission.storage.request();
        if (status.isPermanentlyDenied) {
          // Abre as configurações do app para o usuário habilitar manualmente
          await openAppSettings();
          return false;
        }
        return status.isGranted;
      }
    }
    return true;
  }

  static Future<String?> _getDownloadPath() async {
    if (Platform.isAndroid) {
      try {
        // Usa o diretório de cache do app
        final dir = await getTemporaryDirectory();
        return dir.path;
      } catch (e) {
        debugPrint('Erro ao obter diretório: $e');
        return null;
      }
    }
    return null;
  }

  /// Limpa arquivos APK antigos do diretório de download
  static Future<void> cleanOldUpdates() async {
    try {
      final downloadPath = await _getDownloadPath();
      if (downloadPath == null) return;

      final dir = Directory(downloadPath);
      if (!await dir.exists()) return;

      await for (final file in dir.list()) {
        if (file is File && file.path.endsWith('.apk')) {
          try {
            await file.delete();
          } catch (e) {
            debugPrint('Erro ao deletar APK antigo: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao limpar APKs antigos: $e');
    }
  }
}
