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
        return '';  // Retorna string vazia se houver erro na conversão
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
        player: sanitizeString(json['player']) ?? 'System',
        message: sanitizeString(json['message']) ?? '',
        channel: sanitizeString(json['channel']) ?? 'chat_global',
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
      uptime: json['uptime'] is String ? int.parse(json['uptime']) : (json['uptime'] as num?)?.toInt() ?? 0,
      playersOnline: json['players_online'] is String ? int.parse(json['players_online']) : (json['players_online'] as num?)?.toInt() ?? 0,
      maxPlayers: json['max_players'] is String ? int.parse(json['max_players']) : (json['max_players'] as num?)?.toInt() ?? 0,
    );
  }
}
