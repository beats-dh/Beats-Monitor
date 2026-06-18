import 'dart:async';
import 'dart:convert';

import 'package:beats_monitor/models/events.dart';
import 'package:beats_monitor/models/system_data.dart';
import 'package:beats_monitor/models/websocket_events.dart';
import 'package:beats_monitor/services/config_service.dart';
import 'package:beats_monitor/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WebSocketService createService() {
    SharedPreferences.setMockInitialValues({});
    return WebSocketService(ConfigService())..manualReconnectMode = true;
  }

  Map<String, dynamic> systemPayload() {
    return {
      'cpu': {
        'usage_percent': 12,
        'kernel_time_percent': 3,
        'user_time_percent': 9,
      },
      'memory': {
        'private_usage_mb': 256,
        'working_set_mb': 512,
        'page_fault_count': 4,
        'peak_working_set_mb': 768,
        'quota_paged_pool_mb': 8,
        'quota_peak_paged_pool_mb': 16,
      },
      'process': {'name': 'canary'},
      'system': {
        'cpu': {
          'name': 'Test CPU',
          'usage_percent': 12,
          'idle_time_percent': 88,
          'kernel_time_percent': 3,
          'user_time_percent': 9,
        },
        'cpu_cores': 8,
        'architecture': 9,
        'memory': {
          'available_gb': 12,
          'total_gb': 32,
          'usage_percent': 62.5,
          'performance': {
            'commit': {'total_gb': 20},
          },
        },
      },
    };
  }

  test('routes subscribed websocket events into typed streams', () async {
    final service = createService();
    final chats = <ChatMessage>[];
    final logs = <RuntimeLogEvent>[];
    final systems = <SystemData>[];
    final statuses = <ServerStatus>[];
    final subscriptions = <StreamSubscription>[
      service.chatMessageStream.listen(chats.add),
      service.runtimeLogStream.listen(logs.add),
      service.systemDataStream.listen(systems.add),
      service.serverStatusStream.listen(statuses.add),
    ];

    addTearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      service.dispose();
    });

    service.subscribe([
      WebSocketEvents.chatLocal,
      WebSocketEvents.chatGlobal,
      WebSocketEvents.chatTrade,
      WebSocketEvents.chatHelp,
      WebSocketEvents.chatPrivate,
      WebSocketEvents.chatHistory,
      WebSocketEvents.runtimeLog,
      WebSocketEvents.systemResources,
      WebSocketEvents.serverStatus,
    ]);

    service.handleMessage(jsonEncode({
      'type': 'event',
      'event': WebSocketEvents.chatGlobal,
      'data': {
        'player': 'Waldir',
        'message': 'use !task exactly',
        'timestamp': '1710000000',
        'level': '400',
      },
    }));
    service.handleMessage(jsonEncode({
      'type': 'event',
      'event': WebSocketEvents.chatPrivate,
      'data': {
        'player': 'Tankso',
        'message': 'to Waldir: ja nao',
        'timestamp': 1710000001,
        'level': 500,
      },
    }));
    service.handleMessage(jsonEncode({
      'type': 'event',
      'event': WebSocketEvents.chatHistory,
      'data': {
        'chat_help': [
          {
            'player': 'Helper',
            'message': 'help line',
            'timestamp': 1710000002,
            'level': 50,
          }
        ],
        'chat_private': [
          {
            'player': 'Waldir',
            'message': 'to Tankso: answer',
            'timestamp': 1710000003,
            'level': 600,
          }
        ],
      },
    }));
    service.handleMessage(jsonEncode({
      'type': 'event',
      'event': WebSocketEvents.chatHistory,
      'data': [
        {
          'channel': 'chat_trade',
          'player': 'Seller',
          'message': 'sell item',
          'timestamp': 1710000004,
          'level': 70,
        }
      ],
    }));
    service.handleMessage(jsonEncode({
      'type': 'event',
      'event': WebSocketEvents.runtimeLog,
      'data': {
        'file': 'runtime.log',
        'lines': ['line one', 'line two'],
        'snapshot': true,
        'truncated': false,
        'missing': false,
        'size': '200',
        'mtime_ms': '1710000005000',
      },
    }));
    service.handleMessage(jsonEncode({
      'type': 'event',
      'event': WebSocketEvents.systemResources,
      'data': systemPayload(),
    }));
    service.handleMessage(jsonEncode({
      'type': 'event',
      'event': WebSocketEvents.serverStatus,
      'data': {
        'status': 'online',
        'uptime': '3600',
        'players_online': '12',
        'max_players': '1000',
      },
    }));

    await Future<void>.delayed(Duration.zero);

    expect(chats.map((message) => message.channel), [
      'chat_global',
      'chat_private',
      'chat_help',
      'chat_private',
      'chat_trade',
    ]);
    expect(chats.first.message, 'use !task exactly');
    expect(chats.first.level, 400);
    expect(chats[1].message, 'to Waldir: ja nao');
    expect(logs.single.file, 'runtime.log');
    expect(logs.single.lines, ['line one', 'line two']);
    expect(logs.single.snapshot, isTrue);
    expect(logs.single.size, 200);
    expect(systems.single.processData.processName, 'canary');
    expect(systems.single.systemInfo.cpu.name, 'Test CPU');
    expect(statuses.single.status, 'online');
    expect(statuses.single.playersOnline, 12);
    expect(statuses.single.maxPlayers, 1000);
  });

  test('ignores events that were not subscribed', () async {
    final service = createService();
    final chats = <ChatMessage>[];
    final subscription = service.chatMessageStream.listen(chats.add);

    addTearDown(() async {
      await subscription.cancel();
      service.dispose();
    });

    service.subscribe([WebSocketEvents.chatHelp]);
    service.handleMessage(jsonEncode({
      'type': 'event',
      'event': WebSocketEvents.chatTrade,
      'data': {
        'player': 'Seller',
        'message': 'ignored trade',
        'timestamp': 1710000004,
        'level': 70,
      },
    }));

    await Future<void>.delayed(Duration.zero);

    expect(chats, isEmpty);
  });
}
