import 'package:apexo/core/observable.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

final _s3Result = ObservableState("");
final _emailResult = ObservableState("");

class ProductionTests extends StatefulWidget {
  const ProductionTests({super.key});

  @override
  State<ProductionTests> createState() => _ProductionTestsState();
}

class _ProductionTestsState extends State<ProductionTests> {
  final testEmailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    testEmailController.text = login.email;
  }

  @override
  void dispose() {
    testEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Expander(
        leading: const Icon(FluentIcons.test_case),
        header: Txt(txt("prodTests")),
        contentPadding: const EdgeInsets.all(10),
        content: SizedBox(
          width: 400,
          child: MStreamBuilder(
              streams: [_s3Result.stream, _emailResult.stream],
              builder: (context, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InfoBar(
                      title: Txt(txt("fileStorageTest")),
                      severity: InfoBarSeverity.info,
                      content: Txt(txt("fileStorageTestDesc")),
                    ),
                    Row(
                      children: [
                        FilledButton(
                            child: Txt(txt("fileStorageButton")),
                            onPressed: () async {
                              _s3Result(".");
                              try {
                                await login.pb!.settings.testS3();
                              } catch (e) {
                                _s3Result(
                                    "ERROR: ${txt("fileStorageFail")}: ${e.toString()}");
                                return;
                              }
                              _s3Result(txt("fileStorageSuccess"));
                            }),
                        const SizedBox(width: 10),
                        if (_s3Result().length == 1) const ProgressBar()
                      ],
                    ),
                    if (_s3Result().length > 1) buildTestResult(_s3Result),
                    const SizedBox(height: 20),
                    InfoBar(
                      title: Txt(txt("emailTest")),
                      severity: InfoBarSeverity.info,
                      content: Txt(txt("emailTestDesc")),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CupertinoTextField(
                          placeholder: txt("targetEmail"),
                          controller: testEmailController,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            FilledButton(
                                child: Txt(txt("emailTestButton")),
                                onPressed: () async {
                                  _emailResult(".");
                                  try {
                                    await login.pb!.settings.testEmail(
                                        testEmailController.text,
                                        "password-reset");
                                  } catch (e) {
                                    _emailResult(
                                        "ERROR: ${txt("emailTestFail")}: ${e.toString()}");
                                    return;
                                  }
                                  _emailResult(txt("emailTestSuccess"));
                                }),
                            const SizedBox(width: 10),
                            if (_emailResult().length == 1) const ProgressBar()
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_emailResult().length > 1)
                          buildTestResult(_emailResult),
                      ],
                    ),
                  ]
                      .map((e) => [e, const SizedBox(height: 10)])
                      .expand((e) => e)
                      .toList(),
                );
              }),
        ),
      ),
    );
  }

  InfoBar buildTestResult(ObservableState<String> st) {
    return InfoBar(
      title: st().startsWith("ERROR") ? Txt(txt("fail")) : Txt(txt("success")),
      content: Txt(st()),
      severity: st().startsWith("ERROR")
          ? InfoBarSeverity.error
          : InfoBarSeverity.success,
    );
  }
}
