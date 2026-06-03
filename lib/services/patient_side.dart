import 'package:apexo/core/observable.dart';
import 'package:apexo/features/login/login_controller.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/services/notifications/push_deferring.dart';
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
  String id = "";
  double price = 0;
  double paid = 0;
  DateTime date = DateTime.now();
  List<String> prescriptions = [];
  List<String> imgs = [];
  bool archived = false;
  bool isDone = false;

  PatientAppointment.fromJson(Map<String, dynamic> json) {
    id = json["id"] ?? "";
    price = double.parse((json["price"] ?? price).toString());
    paid = double.parse((json["paid"] ?? paid).toString());
    date = (json["date"] != null
        ? DateTime.fromMillisecondsSinceEpoch((json["date"] * 60000).toInt())
        : date);
    prescriptions = List<String>.from(json["prescriptions"] ?? []);
    imgs = List<String>.from(json["imgs"] ?? []);
    archived = json["archived"] == 1 ? true : false;
    isDone = json["isDone"] == 1 ? true : false;
  }
}

class PatientSide extends ObservablePersistingObject {
  bool initialized = false;
  String server;
  String name;
  String patientID;
  String relayKey;
  String collectionId = "";

  // values taken from settings
  String currency = "";
  String phone = "";
  String countryCode = "";
  String clinicNameAndAddress = "";

  List<PatientAppointment> appointments = [];
  List<String> imgLinks = [];

  PatientSide({
    required this.server,
    required this.name,
    required this.patientID,
    required this.relayKey,
  }) : super("patient-side");

  static fromHref() async {
    await patientSide.box;
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

  static fromQR(Future<XFile?> file) async {
    XFile? res = await file;

    loginCtrl.loadingPatientSide(true);

    if (res == null) return loginCtrl.loadingPatientSide(false);

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

  logoutPatientSide() {
    launch.open(Open.login);
    server = "";
    name = "";
    patientID = "";
    relayKey = "";
    if (kIsWeb) {
      JSBridge.setGlobalVariable("accountId", "");
      JSBridge.setGlobalVariable("shouldShowPrompt", "no");
    }
    notifyAndPersist();
    loginCtrl.finishedLoginProcess();
  }

  Future<void> activate() async {
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

    // Initialize deferred push storage early so stores can safely
    // defer push notifications throughout the rest of activate().
    deferredPush.init(server);

    // getting currency
    final settingsRes = await http.get(Uri.parse(
        "$server/api/collections/data/records?page=1&perPage=500&skipTotal=1"));

    final settingsJson = jsonDecode(settingsRes.body);
    currency = (settingsJson["items"] as List<dynamic>)
            .where((item) => (item["id"] as String).startsWith("currency"))
            .firstOrNull?["data"]?["value"] ??
        "";

    phone = (settingsJson["items"] as List<dynamic>)
            .where((item) => (item["id"] as String).startsWith("phone"))
            .firstOrNull?["data"]?["value"] ??
        "";

    countryCode = (settingsJson["items"] as List<dynamic>)
            .where((item) => (item["id"] as String).startsWith("country"))
            .firstOrNull?["data"]?["value"] ??
        "";

    clinicNameAndAddress = (settingsJson["items"] as List<dynamic>)
            .where((item) =>
                (item["id"] as String).startsWith("prescription_header"))
            .firstOrNull?["data"]?["value"] ??
        "";

    // getting appointments
    final appointmentsRes = await http.get(Uri.parse(
        "$server/api/collections/public/records?page=1&perPage=9999&filter=pid%3D%22$patientID%22"));

    final appointmentsJson = jsonDecode(appointmentsRes.body);

    final items = appointmentsJson["items"] as List<dynamic>;

    if (items.firstOrNull != null) {
      collectionId = items.first["collectionId"] ?? "";
    }

    appointments.clear();
    for (final item in items) {
      appointments.add(PatientAppointment.fromJson(item));
    }

    for (final appointment in appointments) {
      for (var img in appointment.imgs) {
        imgLinks.add("$server/api/files/$collectionId/${appointment.id}/$img");
      }
    }

    loginCtrl.finishedLoginProcess();
    notifyAndPersist();
    loginCtrl.loadingPatientSide(false);

    launch.open(Open.patient);

    try {
      await Messaging.identifyDevice(isPatient: true);
    } catch (e, t) {
      throw Exception("Error while initializing notifications: $e $t");
    }
  }

  String getImgLink(String appointmentId, String imgName) {
    return "$server/api/files/$collectionId/$appointmentId/$imgName";
  }

  String getThumbFromImgLink(String imgLink) {
    return "$imgLink?thumb=100x100";
  }

  @override
  fromJson(Map<String, dynamic> json) {
    server = json["server"] ?? "";
    name = json["name"] ?? "";
    patientID = json["patientID"] ?? "";
    relayKey = json["relayKey"] ?? "";

    if (server.isNotEmpty &&
        name.isNotEmpty &&
        patientID.isNotEmpty &&
        relayKey.isNotEmpty) {
      activate();
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
  img.Image? originalImage = img.decodeImage(b);

  if (originalImage == null) throw Exception("Could not decode image");
  img.Image resizedImage = img.copyResize(originalImage, width: 600);

  final resized = Uint8List.fromList(img.encodeJpg(resizedImage, quality: 70));
  var request = http.MultipartRequest(
      'POST', Uri.parse('https://qrread.alisaleem.workers.dev/'));

  request.files.add(
    http.MultipartFile.fromBytes(
      'file',
      resized,
      filename: xFile.name,
      contentType: MediaType('image', 'png'),
    ),
  );

  var streamedResponse = await request.send();
  var response = await http.Response.fromStream(streamedResponse);
  try {
    final json = jsonDecode(response.body);
    String shortLink = json[0]['symbol'][0]['data'] as String;
    final longLink = (await http.post(Uri.parse(shortLink))).body;
    return decode(longLink.replaceAll("https://web.apexo.app/", "")).split("|");
  } catch (e) {
    return "Error scanning QR: $e ${response.body}";
  }
}
