import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:ffi/ffi.dart';

typedef _EncryptNative = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Double, Double);
typedef _Encrypt = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, double, double);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _Free = void Function(Pointer<Utf8>);

final DynamicLibrary _lib = Platform.isAndroid
    ? DynamicLibrary.open('libencrypt.so')
    : DynamicLibrary.process();

final _Encrypt _encrypt = _lib
    .lookup<NativeFunction<_EncryptNative>>('encrypt_location')
    .asFunction();
final _Free _free = _lib
    .lookup<NativeFunction<_FreeNative>>('free_string')
    .asFunction();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Ready';
  String? _parmsHex;
  String? _publicKeyHex;
  bool _sending = false;
  bool _loadingKeys = false;
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  List<String> _incomingRequests = [];
  String _requestStatus = 'No requests';

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  @override
  void dispose() {
    _userController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _loadParams() async {
    if (_loadingKeys) return;
    setState(() {
      _loadingKeys = true;
      _status = 'Loading encryption keys...';
    });
    try {
      final response = await http.get(Uri.parse('http://10.0.2.2:5000/params'));
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() => _status = 'Key fetch failed (${response.statusCode})');
        return;
      }
      if (response.body.isEmpty) {
        setState(() => _status = 'Key fetch failed (empty response)');
        return;
      }
      final map = Map<String, dynamic>.from(
          jsonDecode(response.body) as Map<String, dynamic>);
      final parms = map['parms'] as String?;
      final pk = map['pk'] as String?;
      if (parms == null || pk == null) {
        setState(() => _status = 'Key fetch failed (missing fields)');
        return;
      }
      setState(() {
        _parmsHex = parms;
        _publicKeyHex = pk;
        _status = 'Ready';
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _status = 'Key fetch error: $err');
    } finally {
      if (!mounted) return;
      setState(() => _loadingKeys = false);
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    final userId = _userController.text.trim();
    if (userId.isEmpty) {
      setState(() => _status = 'Enter your user ID');
      return;
    }
    if (_parmsHex == null || _publicKeyHex == null) {
      await _loadParams();
      if (_parmsHex == null || _publicKeyHex == null) {
        return;
      }
    }

    final loc = Location();
    try {
      setState(() {
        _sending = true;
        _status = 'Requesting location...';
      });
      var serviceEnabled = await loc.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await loc.requestService();
        if (!serviceEnabled) {
          setState(() => _status = 'Location service disabled');
          setState(() => _sending = false);
          return;
        }
      }

      var permission = await loc.hasPermission();
      if (permission == PermissionStatus.denied) {
        permission = await loc.requestPermission();
      }
      if (permission == PermissionStatus.deniedForever) {
        setState(() => _status = 'Location permission permanently denied');
        setState(() => _sending = false);
        return;
      }
      if (permission != PermissionStatus.granted) {
        setState(() => _status = 'Location permission denied');
        setState(() => _sending = false);
        return;
      }

      final data = await loc.getLocation();
      final latitude = data.latitude;
      final longitude = data.longitude;
      if (latitude == null || longitude == null) {
        setState(() => _status = 'Location unavailable');
        setState(() => _sending = false);
        return;
      }

      setState(() => _status = 'Encrypting...');
      final parmsPtr = _parmsHex!.toNativeUtf8();
      final pkPtr = _publicKeyHex!.toNativeUtf8();
      final ptr = _encrypt(parmsPtr, pkPtr, latitude, longitude);
      malloc.free(parmsPtr);
      malloc.free(pkPtr);
      final jsonStr = ptr.toDartString();
      _free(ptr);

      setState(() => _status = 'Sending...');
      final payload = Map<String, dynamic>.from(
          jsonDecode(jsonStr) as Map<String, dynamic>);
      payload['user'] = userId;
      final response = await http.post(
        Uri.parse('http://10.0.2.2:5000/location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (!mounted) return;
      setState(() => _status = 'Sent (${response.statusCode})');
    } catch (err) {
      if (!mounted) return;
      setState(() => _status = 'Error: $err');
    } finally {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  Future<void> _sendRequest() async {
    final userId = _userController.text.trim();
    final targetId = _targetController.text.trim();
    if (userId.isEmpty || targetId.isEmpty) {
      setState(() => _requestStatus = 'Enter both user IDs');
      return;
    }
    setState(() => _requestStatus = 'Sending request...');
    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:5000/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'from': userId, 'to': targetId}),
      );
      if (!mounted) return;
      setState(() => _requestStatus = 'Request sent (${response.statusCode})');
    } catch (err) {
      if (!mounted) return;
      setState(() => _requestStatus = 'Request error: $err');
    }
  }

  Future<void> _loadRequests() async {
    final userId = _userController.text.trim();
    if (userId.isEmpty) {
      setState(() => _requestStatus = 'Enter your user ID');
      return;
    }
    setState(() => _requestStatus = 'Checking requests...');
    try {
      final response = await http.get(
        Uri.parse('http://10.0.2.2:5000/requests/$userId'),
      );
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() => _requestStatus = 'Request check failed');
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final requests = List<String>.from(data['requests'] ?? []);
      setState(() {
        _incomingRequests = requests;
        _requestStatus =
            requests.isEmpty ? 'No pending requests' : 'Pending requests';
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _requestStatus = 'Request check error: $err');
    }
  }

  Future<void> _respondRequest(String fromUser, bool accepted) async {
    final userId = _userController.text.trim();
    if (userId.isEmpty) {
      setState(() => _requestStatus = 'Enter your user ID');
      return;
    }
    setState(() => _requestStatus = 'Sending response...');
    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:5000/respond'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
          {'from': fromUser, 'to': userId, 'accepted': accepted},
        ),
      );
      if (!mounted) return;
      _incomingRequests =
          _incomingRequests.where((item) => item != fromUser).toList();
      setState(() {
        _requestStatus = 'Response sent (${response.statusCode})';
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _requestStatus = 'Response error: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Proximity Alert')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Share your current location securely.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your coordinates are encrypted on-device and sent to the '
                          'local server for proximity checks.',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _userController,
                          decoration: const InputDecoration(
                            labelText: 'Your user ID',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _sending ? null : _send,
                          child: Text(_sending ? 'Sending...' : 'Send Location'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _loadingKeys ? null : _loadParams,
                          child: Text(
                            _loadingKeys ? 'Refreshing Keys...' : 'Refresh Keys',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _status.startsWith('Error') ||
                                    _status.contains('failed') ||
                                    _status.contains('denied')
                                ? Colors.red
                                : Colors.black87,
                          ),
                        ),
                        const Divider(height: 32),
                        const Text(
                          'Invite someone to track with you',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _targetController,
                          decoration: const InputDecoration(
                            labelText: 'Person to invite',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _sendRequest,
                          child: const Text('Send Invite'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _loadRequests,
                          child: const Text('Check Incoming Requests'),
                        ),
                        const SizedBox(height: 8),
                        ..._incomingRequests.map(
                          (requester) => Row(
                            children: [
                              Expanded(child: Text('Request from $requester')),
                              TextButton(
                                onPressed: () =>
                                    _respondRequest(requester, true),
                                child: const Text('Accept'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _respondRequest(requester, false),
                                child: const Text('Decline'),
                              ),
                            ],
                          ),
                        ),
                        if (_incomingRequests.isEmpty)
                          const Text('No pending requests'),
                        const SizedBox(height: 8),
                        Text(
                          _requestStatus,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
