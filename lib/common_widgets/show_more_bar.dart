import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ShowMoreBar extends StatelessWidget {
  const ShowMoreBar(
      {super.key,
      required this.scrollController,
      required this.callBack,
      required this.all,
      required this.slice});
  final ScrollController scrollController;
  final VoidCallback callBack;
  final int all;
  final int slice;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        border: Border(
          top: BorderSide(
            color: theme.resources.cardStrokeColorDefault,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(
            "${txt("showing")} $slice/$all",
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (all > slice)
            Button(
              onPressed: () {
                callBack();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  scrollController.animateTo(
                    scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                  );
                });
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.double_chevron_down, size: 12),
                  const SizedBox(width: 6),
                  Txt(txt("showMore"), style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}