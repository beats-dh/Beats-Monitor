class ServerStatus {
  final int maxPlayers;
  final int playersOnline;
  final String serverIp;
  final String serverLocation;
  final String serverName;
  final String serverVersion;
  final String status;
  final int uptime;

  ServerStatus({
    required this.maxPlayers,
    required this.playersOnline,
    required this.serverIp,
    required this.serverLocation,
    required this.serverName,
    required this.serverVersion,
    required this.status,
    required this.uptime,
  });

  factory ServerStatus.fromJson(Map<String, dynamic> json) {
    final dados = json['dados'] as Map<String, dynamic>;
    return ServerStatus(
      maxPlayers: dados['max_players'] as int,
      playersOnline: dados['players_online'] as int,
      serverIp: dados['server_ip'] as String,
      serverLocation: dados['server_location'] as String,
      serverName: dados['server_name'] as String,
      serverVersion: dados['server_version'] as String,
      status: dados['status'] as String,
      uptime: dados['uptime'] as int,
    );
  }

  String get formattedUptime {
    final hours = uptime ~/ 3600;
    final minutes = (uptime % 3600) ~/ 60;
    final seconds = uptime % 60;
    return '${hours}h ${minutes}m ${seconds}s';
  }
}
