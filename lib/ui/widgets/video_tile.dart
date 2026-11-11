import 'dart:ui';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/roles.dart';
import '../../theme.dart';

const _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// Kachel mit Kamerabild eines Spielers.
class VideoTile extends StatelessWidget {
  const VideoTile({
    super.key,
    required this.name,
    this.renderer,
    this.showVideo = true,
    this.mirror = false,
    this.isSelf = false,
    this.dead = false,
    this.mayor = false,
    this.revealedRole,
    this.selected = false,
    this.onTap,
    this.votes = 0,
    this.tag,
    this.tagColor = AppColors.bloodBright,
    this.muted = false,
    this.connecting = false,
    this.dim = false,
  });

  final String name;
  final RTCVideoRenderer? renderer;
  final bool showVideo;
  final bool mirror;
  final bool isSelf;
  final bool dead;
  final bool mayor;
  final Role? revealedRole;
  final bool selected;
  final VoidCallback? onTap;
  final int votes;
  final String? tag;
  final Color tagColor;
  final bool muted;
  final bool connecting;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    Widget video;
    if (renderer != null && showVideo) {
      video = RTCVideoView(
        renderer!,
        mirror: mirror,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
      if (dead) video = ColorFiltered(colorFilter: _grayscale, child: video);
    } else {
      video = _Silhouette(name: name, connecting: connecting && showVideo);
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: const Color(0xFF0A080B),
          border: Border.all(
            color: selected ? AppColors.bloodBright : AppColors.line,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: [
            if (selected) BoxShadow(color: AppColors.blood.withValues(alpha: 0.7), blurRadius: 18),
          ],
        ),
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              video,
              if (dim) Container(color: Colors.black.withValues(alpha: 0.55)),
              // untere Schattierung für den Namen
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.55, 1],
                    colors: [Colors.transparent, Color(0xE6000000)],
                  ),
                ),
              ),
              if (dead) const _DeadMark(),
              Positioned(
                left: 8,
                right: 8,
                bottom: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (revealedRole != null)
                      Text(
                        revealedRole!.name.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: AppText.display,
                          fontSize: 9,
                          letterSpacing: 1.6,
                          color: AppColors.bloodBright,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Row(
                      children: [
                        if (mayor)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.workspace_premium, size: 14, color: AppColors.ember),
                          ),
                        Expanded(
                          child: Text(
                            isSelf ? '$name (du)' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppText.display,
                              fontSize: 12,
                              letterSpacing: 1.2,
                              color: dead ? AppColors.ash : AppColors.bone,
                              decoration: dead ? TextDecoration.lineThrough : null,
                              decorationColor: AppColors.blood,
                            ),
                          ),
                        ),
                        if (muted) const Icon(Icons.mic_off, size: 13, color: AppColors.ash),
                      ],
                    ),
                  ],
                ),
              ),
              if (tag != null)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Text(
                      tag!.toUpperCase(),
                      style: TextStyle(
                          fontFamily: AppText.display, fontSize: 9, letterSpacing: 1.5, color: tagColor),
                    ),
                  ),
                ),
              if (votes > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.blood,
                      border: Border.all(color: AppColors.bloodBright),
                    ),
                    child: Text(
                      '$votes',
                      style: const TextStyle(
                          fontFamily: AppText.display, fontWeight: FontWeight.w900, color: AppColors.bone),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Silhouette extends StatelessWidget {
  const _Silhouette({required this.name, required this.connecting});
  final String name;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.9,
          colors: [Color(0xFF1C1517), Color(0xFF060507)],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: const TextStyle(
              fontFamily: AppText.display,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Color(0xFF3A2E30),
            ),
          ),
          if (connecting)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('…', style: TextStyle(color: AppColors.ash)),
            ),
        ],
      ),
    );
  }
}

class _DeadMark extends StatelessWidget {
  const _DeadMark();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _ScratchPainter()),
    );
  }
}

class _ScratchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x55200000));
    final p = Paint()
      ..color = AppColors.blood.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    // drei Krallenspuren
    for (var i = 0; i < 3; i++) {
      final dx = size.width * (0.28 + i * 0.16);
      canvas.drawLine(Offset(dx, size.height * 0.12), Offset(dx + size.width * 0.22, size.height * 0.62), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Verschwommenes, namenloses Kamerabild (Blick des kleinen Mädchens).
class PeekView extends StatelessWidget {
  const PeekView({super.key, required this.renderer});
  final RTCVideoRenderer renderer;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: ColorFiltered(
          colorFilter: _grayscale,
          child: RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        ),
      ),
    );
  }
}
