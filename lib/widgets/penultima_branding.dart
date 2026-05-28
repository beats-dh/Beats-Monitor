import 'package:flutter/material.dart';

const penultimaLogoAsset = 'assets/branding/penultima-logo.png';
const penultimaBackgroundAsset = 'assets/branding/penultima-background.jpg';

class PenultimaBackdrop extends StatelessWidget {
  final Widget child;
  final double imageOpacity;

  const PenultimaBackdrop({
    super.key,
    required this.child,
    this.imageOpacity = 0.28,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF07030C)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            penultimaBackgroundAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            opacity: AlwaysStoppedAnimation(imageOpacity),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xE607030C),
                  Color(0xC9080310),
                  Color(0xF3050208),
                ],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xD9000000),
                  Color(0x990B0312),
                  Color(0xE6000000),
                ],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class PenultimaPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const PenultimaPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xD00D0914),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor ?? const Color(0x55B44CFF),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 22,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
