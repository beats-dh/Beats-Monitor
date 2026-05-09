import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
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
  // Usado para armazenar o estado local da conexão
  bool _localConnectionStatus = false;
  
  @override
  void initState() {
    super.initState();
    // Inicializa com o estado atual
    _localConnectionStatus = widget.webSocketService.connectionStatus;
  }
  
  // Verifica se está no Windows
  bool get _isWindows => !kIsWeb && Platform.isWindows;
  
  // Calcula os tamanhos baseado na plataforma
  double _getIconSize(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return _isWindows 
        ? 18 // Tamanho fixo menor para Windows
        : screenSize.width * 0.06;
  }
  
  double _getFontSize(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return _isWindows 
        ? 14 // Tamanho fixo menor para Windows 
        : screenSize.width * 0.04;
  }
  
  double _getButtonFontSize(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return _isWindows 
        ? 12 // Tamanho fixo menor para Windows
        : screenSize.width * 0.035;
  }
  
  double _getBorderRadius(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return _isWindows 
        ? 16 // Valor fixo para Windows
        : screenSize.width * 0.06;
  }
  
  EdgeInsets _getContainerMargin(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return _isWindows
        ? const EdgeInsets.only(
            bottom: 16,
            left: 16,
            right: 16,
          )
        : EdgeInsets.only(
            bottom: bottomPadding + screenSize.height * 0.02,
            left: screenSize.width * 0.04,
            right: screenSize.width * 0.04,
          );
  }
  
  EdgeInsets _getContainerPadding(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    return _isWindows
        ? const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          )
        : EdgeInsets.symmetric(
            horizontal: screenSize.width * 0.04,
            vertical: screenSize.height * 0.012,
          );
  }
  
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Consumer<WebSocketService>(
      builder: (context, webSocketService, _) {
        // Atualiza o estado local baseado no estado do serviço
        _localConnectionStatus = webSocketService.connectionStatus;
        
        if (_localConnectionStatus) {
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
            margin: _getContainerMargin(context),
            padding: _getContainerPadding(context),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha((0.87 * 255).round()),
              borderRadius: BorderRadius.circular(_getBorderRadius(context)),
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
                    size: _getIconSize(context),
                  ),
                ] else ...[
                  SizedBox(
                    width: _getIconSize(context),
                    height: _getIconSize(context),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  ),
                ],
                SizedBox(width: _isWindows ? 8 : MediaQuery.of(context).size.width * 0.03),
                Text(
                  getMessage(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _getFontSize(context),
                  ),
                ),
                if (!isAutoReconnectEnabled || isManualMode || hasReachedMaxAttempts) ...[
                  SizedBox(width: _isWindows ? 8 : MediaQuery.of(context).size.width * 0.03),
                  ElevatedButton(
                    onPressed: () {
                      webSocketService.reconnectManually();
                      
                      // Força atualização do estado após um breve delay
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted) {
                          setState(() {
                            _localConnectionStatus = webSocketService.connectionStatus;
                          });
                        }
                      });
                    },
                    style: _isWindows
                        ? ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            minimumSize: const Size(60, 28),
                          )
                        : null,
                    child: Text(
                      l10n.translate('try_again'),
                      style: TextStyle(
                        fontSize: _getButtonFontSize(context),
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
