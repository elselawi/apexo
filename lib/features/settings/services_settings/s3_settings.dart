import 'package:apexo/core/observable.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

final _s3TestResult = ObservableState("");

class S3Settings extends StatefulWidget {
  const S3Settings({super.key});

  @override
  State<S3Settings> createState() => _S3SettingsState();
}

class _S3SettingsState extends State<S3Settings> {
  final TextEditingController endpointController = TextEditingController();
  final TextEditingController bucketController = TextEditingController();
  final TextEditingController regionController = TextEditingController();
  final TextEditingController accessKeyController = TextEditingController();
  final TextEditingController secretKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadS3Settings();
  }

  Future<void> _loadS3Settings() async {
    try {
      final settings = await login.pb!.settings.getAll();
      final s3 = settings['s3'] ?? {};

      endpointController.text = s3['endpoint'] ?? '';
      bucketController.text = s3['bucket'] ?? '';
      regionController.text = s3['region'] ?? '';
      accessKeyController.text = s3['accessKey'] ?? '';
      secretKeyController.text = s3['secret'] ?? '';
    } catch (e) {
      // Controllers remain empty on error
    }
    setState(() {});
  }

  Future<void> _saveS3Settings() async {
    try {
      await login.pb!.settings.update(body: {
        "s3": {
          "enabled": true,
          "endpoint": endpointController.text,
          "bucket": bucketController.text,
          "region": regionController.text,
          "accessKey": accessKeyController.text,
          "secret": secretKeyController.text,
          "forcePathStyle": false,
        }
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: const Text("Success"),
            content: const Text("S3 settings saved successfully"),
            actions: [
              Button(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: const Text("Error"),
            content: Text("Failed to save S3 settings: $e"),
            actions: [
              Button(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              )
            ],
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    endpointController.dispose();
    bucketController.dispose();
    regionController.dispose();
    accessKeyController.dispose();
    secretKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Expander(
        leading: const Icon(FluentIcons.cloud_upload),
        header: Txt(txt("s3_settings")),
        contentPadding: const EdgeInsets.all(10),
        content: SizedBox(
          width: 400,
          child: MStreamBuilder(
              streams: [_s3TestResult.stream],
              builder: (context, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InfoBar(
                      title: Txt(txt("s3_info_title")),
                      severity: InfoBarSeverity.info,
                      content: Txt(txt("s3_info_desc")),
                    ),
                    const SizedBox(height: 15),
                    Txt(txt("s3_endpoint")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: endpointController,
                      placeholder: "https://s3.amazonaws.com",
                    ),
                    const SizedBox(height: 15),
                    Txt(txt("s3_bucket")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: bucketController,
                      placeholder: "my-bucket",
                    ),
                    const SizedBox(height: 15),
                    Txt(txt("s3_region")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: regionController,
                      placeholder: "us-east-1",
                    ),
                    const SizedBox(height: 15),
                    Txt(txt("s3_accessKey")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: accessKeyController,
                      placeholder: "AKIA...",
                    ),
                    const SizedBox(height: 15),
                    Txt(txt("s3_secretKey")),
                    const SizedBox(height: 5),
                    CupertinoTextField(
                      controller: secretKeyController,
                      placeholder: "...",
                      obscureText: true,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        FilledButton(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(FluentIcons.save),
                              const SizedBox(width: 8),
                              Txt(txt("save")),
                            ],
                          ),
                          onPressed: _saveS3Settings,
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(FluentIcons.test_case),
                              const SizedBox(width: 8),
                              Txt(txt("test")),
                            ],
                          ),
                          onPressed: () async {
                            _s3TestResult(".");
                            try {
                              await login.pb!.settings.testS3();
                              _s3TestResult(txt("s3_test_success"));
                            } catch (e) {
                              _s3TestResult(
                                  "ERROR: ${txt("s3_test_fail")}: ${e.toString()}");
                            }
                          },
                        ),
                        const SizedBox(width: 10),
                        if (_s3TestResult().length == 1) const ProgressBar()
                      ],
                    ),
                    if (_s3TestResult().length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 15),
                        child: InfoBar(
                          title: _s3TestResult().startsWith("ERROR")
                              ? Txt(txt("fail"))
                              : Txt(txt("success")),
                          content: Txt(_s3TestResult()),
                          severity: _s3TestResult().startsWith("ERROR")
                              ? InfoBarSeverity.error
                              : InfoBarSeverity.success,
                        ),
                      ),
                  ]
                      .map((e) => [e, const SizedBox(height: 5)])
                      .expand((e) => e)
                      .toList(),
                );
              }),
        ),
      ),
    );
  }
}
