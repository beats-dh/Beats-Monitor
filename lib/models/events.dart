class ChatMessage {
  final String player;
  final String message;
  final String channel;
  final DateTime timestamp;
  final int level;

  ChatMessage({
    required this.player,
    required this.message,
    required this.channel,
    required this.timestamp,
    required this.level,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    String sanitizeString(dynamic value) {
      if (value == null) return '';

      try {
        return value.toString();
      } catch (e) {
        return ''; // Retorna string vazia se houver erro na conversão
      }
    }

    DateTime parseTimestamp(dynamic value) {
      if (value == null) return DateTime.now();

      try {
        if (value is int) {
          // Servidor envia timestamp em segundos, precisamos converter para milissegundos
          return DateTime.fromMillisecondsSinceEpoch(value * 1000);
        }

        if (value is String) {
          // Tenta converter string para int
          final intValue = int.tryParse(value);
          if (intValue != null) {
            return DateTime.fromMillisecondsSinceEpoch(intValue * 1000);
          }
        }
      } catch (e) {
        // Ignora erros e retorna data atual
      }

      return DateTime.now();
    }

    try {
      return ChatMessage(
        player: sanitizeString(json['player']),
        message: sanitizeString(json['message']),
        channel: sanitizeString(json['channel']),
        timestamp: parseTimestamp(json['timestamp']),
        level: (json['level'] is int)
            ? json['level']
            : (json['level'] is String)
                ? int.tryParse(json['level']) ?? 0
                : 0,
      );
    } catch (e) {
      // Se houver qualquer erro no parsing, retorna uma mensagem de erro
      return ChatMessage(
        player: 'System',
        message: 'Erro ao processar mensagem',
        channel: 'chat_global',
        timestamp: DateTime.now(),
        level: 0,
      );
    }
  }
}

class ServerStatus {
  final String status;
  final int uptime;
  final int playersOnline;
  final int maxPlayers;

  ServerStatus({
    required this.status,
    required this.uptime,
    required this.playersOnline,
    required this.maxPlayers,
  });

  factory ServerStatus.fromJson(Map<String, dynamic> json) {
    return ServerStatus(
      status: json['status']?.toString() ?? 'offline',
      uptime: json['uptime'] is String
          ? int.parse(json['uptime'])
          : (json['uptime'] as num?)?.toInt() ?? 0,
      playersOnline: json['players_online'] is String
          ? int.parse(json['players_online'])
          : (json['players_online'] as num?)?.toInt() ?? 0,
      maxPlayers: json['max_players'] is String
          ? int.parse(json['max_players'])
          : (json['max_players'] as num?)?.toInt() ?? 0,
    );
  }
}

class RuntimeLogEvent {
  final String file;
  final List<String> lines;
  final bool snapshot;
  final bool truncated;
  final bool missing;
  final String? error;
  final int size;
  final DateTime? modifiedAt;

  RuntimeLogEvent({
    required this.file,
    required this.lines,
    required this.snapshot,
    required this.truncated,
    required this.missing,
    required this.error,
    required this.size,
    required this.modifiedAt,
  });

  factory RuntimeLogEvent.fromJson(Map<String, dynamic> json) {
    DateTime? parseModifiedAt(dynamic value) {
      final parsed = value is int
          ? value
          : value is String
              ? int.tryParse(value)
              : null;
      if (parsed == null || parsed <= 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(parsed);
    }

    return RuntimeLogEvent(
      file: json['file']?.toString() ?? 'runtime.log',
      lines: (json['lines'] is List)
          ? (json['lines'] as List).map((line) => line.toString()).toList()
          : const [],
      snapshot: json['snapshot'] == true,
      truncated: json['truncated'] == true,
      missing: json['missing'] == true,
      error: json['error']?.toString(),
      size: json['size'] is int
          ? json['size'] as int
          : int.tryParse(json['size']?.toString() ?? '') ?? 0,
      modifiedAt: parseModifiedAt(json['mtime_ms']),
    );
  }
}
