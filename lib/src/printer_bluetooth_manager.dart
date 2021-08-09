/*
 * esc_pos_bluetooth
 * Created by Andrey Ushakov
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import './enums.dart';

/// Bluetooth printer
class PrinterBluetooth {
  PrinterBluetooth(this._device);
  final BluetoothDevice _device;

  String get name => _device.name;
  String get address => _device.address;
  BluetoothDeviceType get type => _device.type;
}

/// Printer Bluetooth Manager
class PrinterBluetoothManager {
  final FlutterBluetoothSerial _bluetoothManager =
      FlutterBluetoothSerial.instance;
  bool _isSendingData = false;
  // bool _isConnected = false;
  StreamSubscription<BluetoothDiscoveryResult> _discoveringSubscription;

  BluetoothDevice _selectedPrinter;
  BluetoothDevice get selectedPrinter => _selectedPrinter;

  final BehaviorSubject<bool> _isDiscovering = BehaviorSubject.seeded(false);
  Stream<bool> get isDiscoveringStream => _isDiscovering.stream;

  final BehaviorSubject<List<BluetoothDevice>> _discoverResults =
      BehaviorSubject.seeded([]);
  Stream<List<BluetoothDevice>> get discoverResults => _discoverResults.stream;

  Future<void> startDiscovery({Duration timeout}) async {
    final List<BluetoothDevice> _results = [];
    _discoverResults.add([]);

    _isDiscovering.add(true);
    final _bluetoothState = await FlutterBluetoothSerial.instance.state;
    if (_bluetoothState == BluetoothState.STATE_ON) {
      _discoveringSubscription =
          _bluetoothManager.startDiscovery().listen((event) {
        if (!_results.contains(event.device)) {
          _results.add(event.device);
        }
        _discoverResults.add(_results.map((_) => _).toList());
      })
            ..onDone(() {
              _isDiscovering.add(false);
            });

      if (timeout != null) {
        Future.delayed(timeout, () {
          stopDiscovery();
        });
      }
    } else {
      _isDiscovering.add(true);
    }
  }

  Future<void> stopDiscovery() async {
    await _discoveringSubscription?.cancel();
    _isDiscovering?.add(false);
  }

  Future<List<BluetoothDevice>> getPairedDevices() async {
    final _bluetoothState = await FlutterBluetoothSerial.instance.state;
    if (_bluetoothState == BluetoothState.STATE_ON) {
      return await _bluetoothManager.getBondedDevices();
    } else {
      return [];
    }
  }

  void selectPrinter(BluetoothDevice printer) {
    _selectedPrinter = printer;
  }

  Future<PosPrintResult> writeBytes(
    List<int> bytes, {
    Duration timeout,
  }) async {
    final Completer<PosPrintResult> completer = Completer();

    if (_selectedPrinter == null) {
      return Future<PosPrintResult>.value(PosPrintResult.printerNotSelected);
    } else if (_isDiscovering.value) {
      return Future<PosPrintResult>.value(PosPrintResult.discoveryInProgress);
    } else if (_isSendingData) {
      return Future<PosPrintResult>.value(PosPrintResult.sendingData);
    }

    _isSendingData = true;

    // Connect
    // try {
    final BluetoothConnection connection =
        await BluetoothConnection.toAddress(_selectedPrinter.address);

    // connection.input.listen((Uint8List data) {
    //   print('Data incoming: ${ascii.decode(data)}');

    //   if (ascii.decode(data).contains('!')) {
    //     _isSendingData = false;
    //     connection.finish(); // Closing connection
    //     print('Disconnecting by local host');
    //   }
    // }).onDone(() {
    //   _isSendingData = false;
    //   connection.finish();
    //   print('Disconnected by remote request');
    // });

    try {
      connection.output.add(Uint8List.fromList(bytes));
      if (timeout != null)
        connection.output.allSent.then((_) {
          _isSendingData = false;
          connection.finish();
          completer.complete(PosPrintResult.success);
          return _;
        }).timeout(
          timeout,
          onTimeout: () {
            if (_isSendingData) {
              _isSendingData = false;
              connection.finish();
              completer.complete(PosPrintResult.timeout);
            }
          },
        );
      else
        connection.output.allSent.then((_) {
          _isSendingData = false;
          connection.finish();
          completer.complete(PosPrintResult.success);
          return _;
        });
    } catch (e) {
      _isSendingData = false;
      connection.finish();
      rethrow;
    }

    return completer.future;
  }

  Future<PosPrintResult> printTicket(Ticket ticket, {Duration timeout}) async {
    if (ticket == null || ticket.bytes.isEmpty) {
      return Future<PosPrintResult>.value(PosPrintResult.ticketEmpty);
    }
    return writeBytes(ticket.bytes, timeout: timeout);
  }
}
