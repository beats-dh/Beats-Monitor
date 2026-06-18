import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/live_capture_controller.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  static const String _characterName = 'Waldir';
  late final LiveCaptureController _captureController;

  @override
  void initState() {
    super.initState();
    _captureController = LiveCaptureController();
  }

  @override
  void dispose() {
    _captureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.live_tv_rounded),
            const SizedBox(width: 12),
            Text(l10n.translate('live_title')),
          ],
        ),
        actions: [
          AnimatedBuilder(
            animation: _captureController,
            builder: (context, _) {
              if (!_captureController.isLive) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.stop_circle_rounded),
                tooltip: l10n.translate('live_stop'),
                onPressed: _captureController.stop,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _captureController,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                return Padding(
                  padding: EdgeInsets.all(compact ? 12 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusBar(context, l10n),
                      SizedBox(height: compact ? 12 : 16),
                      Expanded(child: _buildLiveFrame(context, l10n)),
                      SizedBox(height: compact ? 12 : 16),
                      _buildControls(context, l10n, compact: compact),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isLive = _captureController.isLive;
    final color = isLive ? Colors.green : theme.colorScheme.primary;
    final statusKey = isLive ? 'live_active' : 'live_idle';
    final source = _captureController.sourceLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        children: [
          Icon(
            isLive ? Icons.sensors_rounded : Icons.person_pin_circle_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              source == null || source.isEmpty
                  ? '${l10n.translate(statusKey)} - ${l10n.translate('live_character').replaceAll('{0}', _characterName)}'
                  : '${l10n.translate(statusKey)} - $source',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveFrame(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: theme.dividerColor.withAlpha(120)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_captureController.isLive)
              _captureController.buildPreview(context)
            else
              _buildEmptyState(context, l10n),
            if (_captureController.isStarting)
              Container(
                color: Colors.black.withAlpha(170),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        l10n.translate('live_starting'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final supported = _captureController.isSupported;
    final error = _captureController.errorMessage;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                supported
                    ? Icons.connected_tv_rounded
                    : Icons.desktop_access_disabled_rounded,
                color: Colors.white70,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                error ??
                    l10n.translate(
                      supported ? 'live_select_source' : 'live_not_supported',
                    ),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.translate(
                  supported ? 'live_select_hint' : 'live_web_only',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    AppLocalizations l10n, {
    required bool compact,
  }) {
    final isLive = _captureController.isLive;
    final isStarting = _captureController.isStarting;
    final supported = _captureController.isSupported;

    final primaryButton = FilledButton.icon(
      onPressed: !supported || isStarting
          ? null
          : isLive
              ? _captureController.stop
              : _captureController.start,
      icon: Icon(
        isLive ? Icons.stop_rounded : Icons.play_arrow_rounded,
      ),
      label: Text(l10n.translate(isLive ? 'live_stop' : 'live_start')),
    );

    final secondary = OutlinedButton.icon(
      onPressed: isStarting ? null : () => Navigator.pop(context),
      icon: const Icon(Icons.arrow_back_rounded),
      label: Text(l10n.translate('back')),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primaryButton,
          const SizedBox(height: 8),
          secondary,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: secondary),
        const SizedBox(width: 12),
        Expanded(child: primaryButton),
      ],
    );
  }
}
