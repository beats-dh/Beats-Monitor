class ChatMessage {
  final String player;
  final String message;
  final String channel;
  final DateTime timestamp;

  ChatMessage({
    required this.player,
    required this.message,
    required this.channel,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      player: json['player']?.toString() ?? 'System',
      message: json['message']?.toString() ?? '',
      channel: json['channel']?.toString() ?? 'chat_global',
      timestamp: json['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] * 1000)
          : DateTime.now(),
    );
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
