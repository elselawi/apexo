part of 'open_dicom_viewer_window.dart';

class _VwBtn extends StatefulWidget {
  const _VwBtn({
    required this.icon,
    this.label,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  State<_VwBtn> createState() => _VwBtnState();
}

class _VwBtnState extends State<_VwBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fgColor = widget.active
        ? const Color(0xFF4CC2FF)
        : Colors.white.withValues(alpha: 0.85);

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 18, color: fgColor),
                if (widget.label != null) ...[
                  const SizedBox(width: 6),
                  Txt(
                    widget.label!,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Vertical slider ──────────────────────────────────────────────

class _VerticalSlider extends StatelessWidget {
  const _VerticalSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.4))),
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: Slider(
                value: clamped, min: min, max: max, onChanged: onChanged),
          ),
        ),
        Text(clamped.toStringAsFixed(0),
            style: TextStyle(
                fontSize: 9, color: Colors.white.withValues(alpha: 0.5))),
      ],
    );
  }
}

// ─── Measurement overlay (CustomPaint) ────────────────────────────
