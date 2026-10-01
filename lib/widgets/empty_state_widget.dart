import 'package:flutter/material.dart';

class EmptyStateWidget extends StatefulWidget {
  final String message;
  final String? subtitle;
  final IconData fallbackIcon;
  final String imageAsset;

  const EmptyStateWidget({
    super.key,
    required this.message,
    this.subtitle,
    required this.fallbackIcon,
    required this.imageAsset,
  });

  @override
  State<EmptyStateWidget> createState() => _EmptyStateWidgetState();
}

class _EmptyStateWidgetState extends State<EmptyStateWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: -8.0, end: 8.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Floating image animation
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _animation.value),
                  child: child,
                );
              },
              child: Image.asset(
                widget.imageAsset,
                height: 180,
                width: 180,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return CircleAvatar(
                    radius: 70,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    child: Icon(
                      widget.fallbackIcon,
                      size: 70,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),

            // Message (Title) in Urdu Jameel font
            Text(
              widget.message,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'Jameel Noori Nastaleeq',
              ),
              textAlign: TextAlign.center,
            ),

            // Subtitle if any
            if (widget.subtitle != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.subtitle!,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey.shade600,
                  fontFamily: 'Jameel Noori Nastaleeq',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
