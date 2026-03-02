import 'package:flutter/material.dart';

/// Shimmer loading effect — uses a single animation controller per skeleton
class _ShimmerPainter extends CustomPainter {
  final double progress;
  final Color baseColor;
  final Color shineColor;
  final double borderRadius;

  _ShimmerPainter({
    required this.progress,
    required this.baseColor,
    required this.shineColor,
    this.borderRadius = 8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [baseColor, shineColor, baseColor],
        stops: [
          (progress - 0.3).clamp(0.0, 1.0),
          progress,
          (progress + 0.3).clamp(0.0, 1.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.progress != progress;
}

/// File list skeleton for loading state — single animation controller
class FileListSkeleton extends StatefulWidget {
  final int itemCount;
  const FileListSkeleton({super.key, this.itemCount = 8});

  @override
  State<FileListSkeleton> createState() => _FileListSkeletonState();
}

class _FileListSkeletonState extends State<FileListSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFE0E0E0);
    final shineColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.itemCount,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CustomPaint(
                    size: const Size(40, 40),
                    painter: _ShimmerPainter(
                      progress: _controller.value,
                      baseColor: baseColor,
                      shineColor: shineColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CustomPaint(
                          size: Size(80.0 + (index % 3) * 40, 14),
                          painter: _ShimmerPainter(
                            progress: _controller.value,
                            baseColor: baseColor,
                            shineColor: shineColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        CustomPaint(
                          size: Size(50.0 + (index % 2) * 20, 10),
                          painter: _ShimmerPainter(
                            progress: _controller.value,
                            baseColor: baseColor,
                            shineColor: shineColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Connection card skeleton for dashboard loading — single animation controller
class ConnectionCardSkeleton extends StatefulWidget {
  const ConnectionCardSkeleton({super.key});

  @override
  State<ConnectionCardSkeleton> createState() => _ConnectionCardSkeletonState();
}

class _ConnectionCardSkeletonState extends State<ConnectionCardSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFE0E0E0);
    final shineColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CustomPaint(
                  size: const Size(44, 44),
                  painter: _ShimmerPainter(
                    progress: _controller.value,
                    baseColor: baseColor,
                    shineColor: shineColor,
                    borderRadius: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomPaint(
                        size: const Size(120, 16),
                        painter: _ShimmerPainter(
                          progress: _controller.value,
                          baseColor: baseColor,
                          shineColor: shineColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      CustomPaint(
                        size: const Size(180, 12),
                        painter: _ShimmerPainter(
                          progress: _controller.value,
                          baseColor: baseColor,
                          shineColor: shineColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
