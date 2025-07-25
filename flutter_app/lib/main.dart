import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:ffi/ffi.dart';

typedef _EncryptNative = Pointer<Utf8> Function(Double, Double);
typedef _Encrypt = Pointer<Utf8> Function(double, double);
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<void> _send() async {
    Location loc = Location();
    final data = await loc.getLocation();
    final ptr = _encrypt(data.latitude!, data.longitude!);
    final jsonStr = ptr.toDartString();
    _free(ptr);
    await http.post(Uri.parse('http://10.0.2.2:5000/location'),
        headers: {'Content-Type': 'application/json'}, body: jsonStr);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Proximity App')),
        body: Center(
          child: ElevatedButton(
            onPressed: _send,
            child: const Text('Send Location'),
          ),
        ),
      ),
    );
  }
}
