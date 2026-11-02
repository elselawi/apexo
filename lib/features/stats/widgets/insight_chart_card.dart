import 'package:apexo/features/stats/insights_data.dart';
import 'package:apexo/features/stats/widgets/charts/_common.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class InsightChartCard extends StatefulWidget {
  const InsightChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.labels,
    required this.series,
    required this.names,
    required this.chart,
    this.controls,
    this.money = false,
    this.decimalDigits,
    this.dimensionLabel,
    this.colors = insightColors,
    this.icon = FluentIcons.chart,
  });

  final String title, subtitle;
  final String? dimensionLabel;
  final List<String> labels, names;
  final List<List<double>> series;
  final Widget chart;
  final Widget? controls;
  final bool money;
  final int? decimalDigits;
  final List<Color> colors;
  final IconData icon;

  @override
  State<InsightChartCard> createState() => _InsightChartCardState();
}

class _InsightChartCardState extends State<InsightChartCard> {
  bool table = false;
  bool copied = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(
          text: insightsCsv(widget.labels, widget.names, widget.series,
              widget.dimensionLabel ?? txt('insightsPeriod'))));
      if (!mounted) return;
      setState(() => copied = true);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => copied = false);
    } catch (_) {
      // Clipboard access can be denied by browser or operating-system policy.
      if (!mounted) return;
      await displayInfoBar(context,
          builder: (context, close) => InfoBar(
                title: Txt(txt('error')),
                severity: InfoBarSeverity.error,
                onClose: close,
              ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final color = widget.colors.first;
    return Card(
      padding: const EdgeInsets.all(20),
      borderColor: Colors.transparent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 34, height: 34,
            child: Icon(widget.icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Txt(widget.title, style: theme.typography.bodyStrong?.copyWith(letterSpacing: -0.2)),
                const SizedBox(height: 5),
                Txt(widget.subtitle, style: theme.typography.caption),
              ])),
          const SizedBox(width: 8),
          Tooltip(
              message: txt(table ? 'insightsChart' : 'insightsTable'),
              child: IconButton(
                icon: Icon(table ? FluentIcons.chart : FluentIcons.table,
                    size: 16),
                onPressed: () => setState(() => table = !table),
              )),
          Tooltip(
              message: txt(copied ? 'insightsCopied' : 'insightsCopy'),
              child: IconButton(
                icon: Icon(copied ? FluentIcons.check_mark : FluentIcons.copy,
                    size: 16),
                onPressed: _copy,
              )),
        ]),
        if (widget.controls != null) ...[
          const SizedBox(height: 12),
          widget.controls!,
        ],
        const SizedBox(height: 16),
        Expanded(child: table ? _table(context) : Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 14, 0),
          child: widget.chart,
        )),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 6, children: [
          for (var index = 0; index < widget.names.length; index++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 16,
                  height: 5,
                  decoration: BoxDecoration(
                    color: widget.colors[index % widget.colors.length],
                    borderRadius: BorderRadius.circular(4),
                  )),
              const SizedBox(width: 6),
              Flexible(
                  child: Txt(widget.names[index],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.caption)),
            ]),
        ]),
      ]),
    );
  }

  Widget _table(BuildContext context) {
    if (widget.labels.isEmpty) return const ChartEmptyState();
    final format = NumberFormat.decimalPatternDigits(
        locale: locale.s.$code,
        decimalDigits: widget.decimalDigits ?? (widget.money ? 2 : 0));
    return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: (130.0 + widget.names.length * 120)
                    .clamp(constraints.maxWidth, double.infinity),
                child: Column(children: [
                  _row([widget.dimensionLabel ?? txt('insightsPeriod'), ...widget.names], header: true),
                  Expanded(
                      child: ListView.builder(
                    itemCount: widget.labels.length,
                    itemBuilder: (context, index) => _row([
                      widget.labels[index],
                      ...widget.series
                          .map((values) => format.format(values[index])),
                    ]),
                  )),
                ]),
              ),
            ));
  }

  Widget _row(List<String> values, {bool header = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: FluentTheme.of(context)
                        .resources
                        .dividerStrokeColorDefault))),
        child: Row(children: [
          for (final value in values)
            Expanded(
                child: Text(value,
                    style: header
                        ? FluentTheme.of(context).typography.bodyStrong
                        : null,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
        ]),
      );
}
