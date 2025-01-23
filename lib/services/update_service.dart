import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/api_service.dart';

class UpdateInfo {
  final String version;
  final String url;
  final String changelog;
  final bool required;

  UpdateInfo({
    required this.version,
    required this.url,
    required this.changelog,
    required this.required,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    String changelog = json['changelog'] as String;
    try {
      // Tenta várias codificações até encontrar a correta
      changelog = utf8.decode(latin1.encode(changelog));
    } catch (e) {
      debugPrint('Erro ao decodificar changelog: $e');
      try {
        changelog = utf8.decode(utf8.encode(changelog));
      } catch (e) {
        debugPrint('Segundo erro ao decodificar changelog: $e');
      }
    }

    return UpdateInfo(
      version: json['version'] as String,
      url: json['url'] as String,
      changelog: changelog,
      required: json['required'] as bool,
    );
  }
}

class UpdateService {
  static UpdateService? _instance;
  PackageInfo? _packageInfo;
  
  UpdateService._();
  
  static UpdateService get instance {
    _instance ??= UpdateService._();
    return _instance!;
  }

  Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  String get currentVersion => _packageInfo?.version ?? '0.0.0';

  Future<UpdateInfo?> checkForUpdates() async {
    try {
      debugPrint('Verificando atualizações...');
      
      final response = await ApiService.post(
        'check-update',
        body: {
          'currentVersion': currentVersion,
          'platform': "android",
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['hasUpdate'] == true) {
          return UpdateInfo.fromJson(data['updateInfo']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Erro ao verificar atualizações: $e');
      return null;
    }
  }

  bool shouldUpdate(String newVersion) {
    final current = currentVersion.split('.');
    final new_ = newVersion.split('.');
    
    for (var i = 0; i < 3; i++) {
      final currentNum = int.parse(current[i]);
      final newNum = int.parse(new_[i]);
      
      if (newNum > currentNum) return true;
      if (newNum < currentNum) return false;
    }
    
    return false;
  }
}
