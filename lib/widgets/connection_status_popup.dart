import 'package:flutter/material.dart';
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
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: widget.webSocketService.connectionStatus,
      builder: (context, snapshot) {
        final bool shouldShow = snapshot.hasData && 
                              !snapshot.data! && 
                              mounted;

        if (shouldShow != _visible) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              setState(() => _visible = shouldShow);
            }
          });
        }

        if (!_visible) {
          return const SizedBox.shrink();
        }

        return AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 300),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + MediaQuery.of(context).size.height * 0.02,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width * 0.06,
                vertical: MediaQuery.of(context).size.height * 0.015,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha((0.87 * 255).round()),
                borderRadius: BorderRadius.circular(25.0),
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
                  if (widget.webSocketService.manualReconnectMode) ...[
                    Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: MediaQuery.of(context).size.width * 0.05,
                    ),
                  ] else ...[
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.05,
                      height: MediaQuery.of(context).size.width * 0.05,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                      ),
                    ),
                  ],
                  SizedBox(width: MediaQuery.of(context).size.width * 0.03),
                  Text(
                    widget.webSocketService.manualReconnectMode 
                        ? 'Conexão falhou'
                        : 'Reconectando...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: MediaQuery.of(context).size.width * 0.04,
                    ),
                  ),
                  if (widget.webSocketService.manualReconnectMode) ...[
                    SizedBox(width: MediaQuery.of(context).size.width * 0.04),
                    TextButton(
                      onPressed: () => widget.webSocketService.reconnectManually(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: MediaQuery.of(context).size.width * 0.04,
                        ),
                      ),
                      child: Text(
                        'Tentar Novamente',
                        style: TextStyle(
                          fontSize: MediaQuery.of(context).size.width * 0.035,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
