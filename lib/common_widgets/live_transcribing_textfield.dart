import 'package:apexo/common_widgets/live_transcription_button.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/network.dart';
import 'package:flutter/cupertino.dart';

/// Where a [LiveTranscribingTextField] places its transcription button.
enum MicPlacement {
  /// At the field's bottom-end corner (default).
  end,

  /// Horizontally centred along the field's bottom edge — for circular fields.
  bottomCenter,

  /// No transcription button at all.
  none,
}

/// Whether dictation is available right now: the microphone is only offered
/// when the app is online and AI services are switched on.
bool get transcriptionAvailable =>
    network.isOnline() && globalSettings.aiServicesEnabled;

/// A [CupertinoTextField] with a built-in live-transcription mic button.
///
/// The mic is positioned at the bottom-end of the text field (RTL-aware).
/// When AI services are unavailable, it degrades to a plain text field
/// with normal padding.
///
/// [onTranscriptionDone] is called when a transcription session finishes,
/// with an automatic `mounted` guard — no need to check it yourself.
class LiveTranscribingTextField extends StatefulWidget {
  const LiveTranscribingTextField({
    super.key,
    this.controller,
    this.placeholder,
    this.expands = true,
    this.maxLines,
    this.padding,
    this.onChanged,
    this.autofocus,
    this.onTranscriptionDone,
    this.style,
    this.prefix,
    this.onSubmitted,
    this.micPlacement = MicPlacement.end,
    this.decoration,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final bool expands;
  final int? maxLines;
  final EdgeInsetsGeometry? padding;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onTranscriptionDone;
  final TextStyle? style;
  final bool? autofocus;
  final Widget? prefix;
  final ValueChanged<String>? onSubmitted;
  final MicPlacement micPlacement;

  /// Painted behind the text. Left null the platform's own grey field box is
  /// used; pass a [BoxDecoration] to paint the field the caller's way — for
  /// instance none at all, on a surface that already carries the colour.
  final BoxDecoration? decoration;

  @override
  State<LiveTranscribingTextField> createState() =>
      _LiveTranscribingTextFieldState();
}

class _LiveTranscribingTextFieldState extends State<LiveTranscribingTextField> {
  final TextEditingController _controller = TextEditingController();

  TextEditingController get _effectiveController =>
      widget.controller ?? _controller;

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// The text field itself.
  ///
  /// [CupertinoTextField] only applies its own box decoration when the
  /// `decoration` argument is left off, so a field whose caller brought a
  /// decoration — including `const BoxDecoration()`, which paints nothing — is
  /// built without it, and every other field keeps the platform's own box.
  Widget _field({required bool showMic}) {
    final decoration = widget.decoration;
    return decoration == null
        ? CupertinoTextField(
            style: widget.style,
            expands: widget.expands,
            maxLines: widget.maxLines,
            controller: _effectiveController,
            autofocus: widget.autofocus ?? false,
            padding: _padding(showMic: showMic),
            onChanged: widget.onChanged,
            placeholder: widget.placeholder,
            prefix: widget.prefix,
            onSubmitted: widget.onSubmitted,
          )
        : CupertinoTextField(
            style: widget.style,
            expands: widget.expands,
            maxLines: widget.maxLines,
            controller: _effectiveController,
            autofocus: widget.autofocus ?? false,
            padding: _padding(showMic: showMic),
            decoration: decoration,
            onChanged: widget.onChanged,
            placeholder: widget.placeholder,
            prefix: widget.prefix,
            onSubmitted: widget.onSubmitted,
          );
  }

  EdgeInsetsGeometry _padding({required bool showMic}) {
    return widget.padding ??
        (widget.micPlacement == MicPlacement.bottomCenter
            ? EdgeInsetsDirectional.only(
                start: 7,
                top: 7,
                bottom: showMic ? 40 : 7,
                end: 7,
              )
            : EdgeInsetsDirectional.only(
                start: 7,
                top: 7,
                bottom: 7,
                end: showMic ? 44 : 7,
              ));
  }

  @override
  Widget build(BuildContext context) {
    final showMic =
        widget.micPlacement != MicPlacement.none && transcriptionAvailable;
    final mic = LiveTranscriptionButton(
      textController: _effectiveController,
      onDone: (text) {
        if (mounted) {
          (widget.onTranscriptionDone ?? widget.onChanged)?.call(text);
        }
      },
    );
    return Stack(
      children: [
        _field(showMic: showMic),
        if (showMic)
          widget.micPlacement == MicPlacement.bottomCenter
              ? Positioned(
                  bottom: 2.5,
                  left: 0,
                  right: 0,
                  child: Center(child: mic),
                )
              : PositionedDirectional(
                  bottom: 2.5,
                  end: 2.5,
                  child: mic,
                ),
      ],
    );
  }
}
