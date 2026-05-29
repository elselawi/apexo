import 'dart:convert';
import 'package:http/http.dart' as http;

const String _urlPath = 'https://api.country.is/';
Future<String> getCountryCode() async {
  final response = await http.get(Uri.parse(_urlPath));
  final Map<String, dynamic> data = jsonDecode(response.body);
  final res = data['country'];
  return (res is String && res.length == 2) ? res : "US";
}
