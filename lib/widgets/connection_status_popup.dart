import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/websocket_service.dart';

class ConnectionStatusPopup extends StatefulWidget {
  final WebSocketService webSocketService;

  const ConnectionStatusPopup({
    super.key,
    required this.webSocketService,
  });

  @override
  State<ConnectionStatusPopup> createState() => _ConnectionStatusPopupState();
}

class _ConnectionStatusPopupState extends State<ConnectionStatusPopup> {
  bool _localConnectionStatus = false;

  @override
  void initState() {
    super.initState();
    _localConnectionStatus = widget.webSocketService.connectionStatus;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Consumer<WebSocketService>(
      builder: (context, webSocketService, _) {
        _localConnectionStatus = webSocketService.connectionStatus;

        if (_localConnectionStatus) {
          return const SizedBox.shrink();
        }

        final isManualMode = webSocketService.manualReconnectMode;
        final hasReachedMaxAttempts = webSocketService.reconnectAttempts >=
            webSocketService.maxReconnectAttempts;
        final isAutoReconnectEnabled = webSocketService.autoReconnect;
        final needsManualAction =
            !isAutoReconnectEnabled || isManualMode || hasReachedMaxAttempts;

        String getMessage() {
          if (needsManualAction) {
            return l10n.translate('connection_failed');
          }
          final attempts = l10n
              .translate('reconnect_attempts')
              .replaceAll('{current}', '${webSocketService.reconnectAttempts}')
              .replaceAll('{max}', '${webSocketService.maxReconnectAttempts}');
          return '${l10n.translate('trying_reconnect')} ($attempts)';
        }

        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: math.min(MediaQuery.sizeOf(context).width - 24, 560),
            ),
            margin: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 14,
              left: 12,
              right: 12,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xEE050209),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x664A1F72)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (needsManualAction)
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 18,
                  )
                else
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFFB347)),
                    ),
                  ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    getMessage(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (needsManualAction) ...[
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      webSocketService.reconnectManually();
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted) {
                          setState(() {
                            _localConnectionStatus =
                                webSocketService.connectionStatus;
                          });
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: const Size(60, 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      l10n.translate('try_again'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
