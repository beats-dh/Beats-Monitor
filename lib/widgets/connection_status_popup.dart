import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../l10n/app_localizations.dart';

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
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final l10n = AppLocalizations.of(context);

    return Consumer<WebSocketService>(
      builder: (context, webSocketService, _) {
        final isConnected = webSocketService.connectionStatus;

        if (isConnected) {
          return const SizedBox.shrink();
        }

        final bool isManualMode = webSocketService.manualReconnectMode;
        final bool hasReachedMaxAttempts = webSocketService.reconnectAttempts >= webSocketService.maxReconnectAttempts;
        final bool isAutoReconnectEnabled = webSocketService.autoReconnect;

        String getMessage() {
          if (!isAutoReconnectEnabled || isManualMode || hasReachedMaxAttempts) {
            return l10n.translate('connection_failed');
          }
          final attempts = l10n.translate('reconnect_attempts')
              .replaceAll('{current}', '${webSocketService.reconnectAttempts}')
              .replaceAll('{max}', '${webSocketService.maxReconnectAttempts}');
          return '${l10n.translate('trying_reconnect')} ($attempts)';
        }

        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: EdgeInsets.only(
              bottom: bottomPadding + screenSize.height * 0.02,
              left: screenSize.width * 0.04,
              right: screenSize.width * 0.04,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: screenSize.width * 0.04,
              vertical: screenSize.height * 0.012,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha((0.87 * 255).round()),
              borderRadius: BorderRadius.circular(screenSize.width * 0.06),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha((0.1 * 255).round()),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isAutoReconnectEnabled || isManualMode || hasReachedMaxAttempts) ...[
                  Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: screenSize.width * 0.06,
                  ),
                ] else ...[
                  SizedBox(
                    width: screenSize.width * 0.06,
                    height: screenSize.width * 0.06,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  ),
                ],
                SizedBox(width: screenSize.width * 0.03),
                Text(
                  getMessage(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: screenSize.width * 0.04,
                  ),
                ),
                if (!isAutoReconnectEnabled || isManualMode || hasReachedMaxAttempts) ...[
                  SizedBox(width: screenSize.width * 0.03),
                  ElevatedButton(
                    onPressed: () {
                      webSocketService.reconnectManually();
                    },
                    child: Text(
                      l10n.translate('try_again'),
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.035,
                      ),
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
