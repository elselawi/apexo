import 'package:apexo/core/persistence/observable_persisting_object.dart';
import 'dart:async';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/services/notifications/listeners.dart';
import 'package:apexo/services/notifications/push_deferring.dart';
import 'package:apexo/services/notifications/static_notifications.dart';
import 'package:apexo/utils/href/href_service.dart';
import 'package:apexo/utils/js/js_bridge.dart';
import 'package:apexo/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:apexo/utils/encode.dart';
import 'package:http_parser/http_parser.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class PatientAppointment {
  PatientAppointment.fromJson(Map<String, dynamic> json) {
    id = json["id"] as String? ?? "";
    price = double.parse((json["price"] ?? price).toString());
    paid = double.parse((json["paid"] ?? paid).toString());
    date = (json["date"] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            ((json["date"] as num) * 60000).toInt())
        : date);
    prescriptions =
        List<String>.from(json["prescriptions"] as List<dynamic>? ?? []);
    imgs = List<String>.from(json["imgs"] as List<dynamic>? ?? []);
    archived = json["archived"] == 1 || json["archived"] == true;
    isDone = json["isDone"] == 1 || json["isDone"] == true;
  }
  String id = "";
  double price = 0;
  double paid = 0;
  DateTime date = DateTime.now();
  List<String> prescriptions = [];
  List<String> imgs = [];
  bool archived = false;
  bool isDone = false;
}

class PatientSide extends ObservablePersistingObject {
  PatientSide({
    required this.server,
    required this.name,
    required this.patientID,
    required this.relayKey,
    Future<http.Response> Function(Uri)? httpGet,
    Future<void> Function()? identifyDevice,
  })  : _httpGet = httpGet ?? http.get,
        _identifyDevice =
            identifyDevice ?? (() => Messaging.identifyDevice(isPatient: true)),
        super("patient-side");
  final Future<http.Response> Function(Uri) _httpGet;
  final Future<void> Function() _identifyDevice;
  bool initialized = false;
  String server;
  String name;
  String patientID;
  String relayKey;
  String collectionId = "";
  int _activationGeneration = 0;

  // values taken from settings
  String currency = "";
  String phone = "";
  String countryCode = "";
  String clinicNameAndAddress = "";

  List<PatientAppointment> appointments = [];
  List<String> imgLinks = [];

  static Future<void> fromHref() async {
    await patientSide.ready;
    final url = getUrl();
    try {
      String code = Uri.parse(url).path;
      if (code.isEmpty) return;
      if (code.startsWith("/")) code = code.substring(1);
      if (code.isNotEmpty) {
        final decodedList = decode(code).split("|");
        if (decodedList.length == 4) {
          patientSide.patientID = decodedList[0];
          patientSide.name = decodedList[1];
          patientSide.server = decodedList[2];
          patientSide.relayKey = decodedList[3];
          try {
            await patientSide.activate();
          } catch (e) {
            loginCtrl.loginError(e.toString());
          }
        }
      }
    } catch (e, t) {
      logger("Error while reading href ($url) $e", t);
    }
  }

  static Future<void> fromQR(Future<XFile?> file) async {
    final XFile? res = await file;

    loginCtrl.loadingPatientSide(true);

    if (res == null) {
      loginCtrl.loadingPatientSide(false);
      return;
    }

    try {
      final result = await compute(_scanQRAPI, res);

      if (result is List<String>) {
        patientSide.patientID = result[0];
        patientSide.name = result[1];
        patientSide.server = result[2];
        patientSide.relayKey = result[3];

        try {
          await patientSide.activate();
        } catch (e) {
          loginCtrl.loginError(e.toString());
        }
      } else {
        loginCtrl.loginError(result.toString());
      }
    } catch (e, t) {
      loginCtrl.loginError("Error while reading or decoding QR $e");
      logger("Error while reading or decoding QR", t);
    } finally {
      loginCtrl.loadingPatientSide(false);
    }
  }

  void logoutPatientSide() {
    _activationGeneration++;
    launch.open(Open.login);
    server = "";
    name = "";
    patientID = "";
    relayKey = "";
    if (kIsWeb) {
      JSBridge.setGlobalVariable("accountId", "");
      JSBridge.setGlobalVariable("shouldShowPrompt", "no");
    }
    deferredPush.reset();
    staticNotifications.clear();
    resetStaticNotificationDedupe();
    notifyAndPersist();
    loginCtrl.finishedLoginProcess();
  }

  Future<void> activate() async {
    final activation = ++_activationGeneration;
    loginCtrl.loadingPatientSide(true);
    if (server.isEmpty ||
        name.isEmpty ||
        patientID.isEmpty ||
        relayKey.isEmpty) {
      loginCtrl.loginError("Patient Side URL, Name or ID is empty");
      loginCtrl.loadingPatientSide(false);
      return;
    }

    loginCtrl.loginError("");

    // The patient ID comes from an untrusted link/QR and is interpolated
    // into a PocketBase filter + query param. Restrict it to a safe
    // identifier charset so it can never inject filter syntax.
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(patientID)) {
      loginCtrl.loginError("Invalid patient link");
      loginCtrl.loadingPatientSide(false);
      return;
    }

    try {
      // Initialize deferred push storage early so stores can safely
      // defer push notifications throughout the rest of activate().
      deferredPush.init(server);

      // getting currency
      final settingsRes = await _httpGet(Uri.parse(
          "$server/api/collections/data/records?page=1&perPage=500&skipTotal=1"));
      if (activation != _activationGeneration) return;

      final settingsJson = jsonDecode(settingsRes.body) as Map<String, dynamic>;
      final settings = (settingsJson['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      String settingValue(String prefix) {
        final row = settings.where((item) =>
            (item['id'] as String).startsWith(prefix)).firstOrNull;
        final data = row?['data'] as Map<String, dynamic>?;
        return data?['value'] as String? ?? '';
      }
      currency = settingValue('currency');
      phone = settingValue('phone');
      countryCode = settingValue('country');
      clinicNameAndAddress = settingValue('prescription_header');

      // getting appointments
      final appointmentsRes = await _httpGet(Uri.parse(
          "$server/api/collections/public/records?page=1&perPage=9999&filter=pid%3D%22$patientID%22&pid=$patientID"));
      if (activation != _activationGeneration) return;

      final appointmentsJson = jsonDecode(appointmentsRes.body) as Map<String, dynamic>;

      final items = (appointmentsJson["items"] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      if (items.firstOrNull != null) {
        collectionId = items.first["collectionId"] as String? ?? "";
      }

      appointments.clear();
      imgLinks.clear();
      for (final item in items) {
        appointments
            .add(PatientAppointment.fromJson(item));
      }

      for (final appointment in appointments) {
        for (var img in appointment.imgs) {
          imgLinks
              .add("$server/api/files/$collectionId/${appointment.id}/$img");
        }
      }

      loginCtrl.finishedLoginProcess();
      notifyAndPersist();

      launch.open(Open.patient);

      // Patient data has loaded and the patient screen is open at this point.
      // Device registration is useful for push notifications but is not a
      // prerequisite for using patient-side, so a registration failure must
      // not turn a successful activation into a failed login.
      try {
        await _identifyDevice();
        if (activation != _activationGeneration) return;
      } catch (e, stackTrace) {
        logger("Error while registering patient device: $e", stackTrace);
      }
    } catch (e) {
      loginCtrl.loginError(e.toString());
      rethrow;
    } finally {
      if (activation == _activationGeneration) {
        loginCtrl.loadingPatientSide(false);
      }
    }
  }

  String getImgLink(String appointmentId, String imgName) {
    return "$server/api/files/$collectionId/$appointmentId/$imgName";
  }

  String getThumbFromImgLink(String imgLink) {
    final uri = Uri.parse(imgLink);
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      "thumb": "100x100"
    }).toString();
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    server = json["server"] as String? ?? "";
    name = json["name"] as String? ?? "";
    patientID = json["patientID"] as String? ?? "";
    relayKey = json["relayKey"] as String? ?? "";

    if (server.isNotEmpty &&
        name.isNotEmpty &&
        patientID.isNotEmpty &&
        relayKey.isNotEmpty) {
      unawaited(activate().catchError((_) {}));
    }
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "server": server,
      "name": name,
      "patientID": patientID,
      "relayKey": relayKey,
    };
  }
}

final PatientSide patientSide =
    PatientSide(server: "", name: "", patientID: "", relayKey: "");

Future<dynamic> _scanQRAPI(XFile xFile) async {
  final Uint8List b = await xFile.readAsBytes();
  final img.Image? originalImage = img.decodeImage(b);

  if (originalImage == null) throw Exception("Could not decode image");
  final img.Image resizedImage = img.copyResize(originalImage, width: 600);

  final resized = Uint8List.fromList(img.encodeJpg(resizedImage, quality: 70));
  final request = http.MultipartRequest(
      'POST', Uri.parse('https://qrread.alisaleem.workers.dev/'));

  request.files.add(
    http.MultipartFile.fromBytes(
      'file',
      resized,
      filename: xFile.name,
      contentType: MediaType('image', 'png'),
    ),
  );

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);
  try {
    final results = jsonDecode(response.body) as List<dynamic>;
    final result = results.first as Map<String, dynamic>;
    final symbols = result['symbol'] as List<dynamic>;
    final symbol = symbols.first as Map<String, dynamic>;
    final shortLink = symbol['data'] as String;
    final longLink = (await http.post(Uri.parse(shortLink))).body;
    return decode(longLink.replaceAll("https://web.apexo.app/", "")).split("|");
  } catch (e) {
    return "Error scanning QR: $e ${response.body}";
  }
}
