import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart' as pbt;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;

class PrinterBluetoothInfo {
  final String name;
  final String macAdress;

  PrinterBluetoothInfo({
    required this.name,
    required this.macAdress,
  });
}

class BluetoothPrinterService {
  static final BluetoothPrinterService _instance = BluetoothPrinterService._internal();
  factory BluetoothPrinterService() => _instance;
  BluetoothPrinterService._internal();

  PrinterBluetoothInfo? _connectedDevice;

  /// Request necessary permissions for Bluetooth
  Future<bool> requestPermissions() async {
    // Check if Bluetooth permission is granted
    bool isGranted = await pbt.PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!isGranted) {
      // Request location permission for older Android versions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      
      return statuses.values.any((status) => 
          status == PermissionStatus.granted || 
          status == PermissionStatus.limited);
    }
    return true;
  }

  /// Check if Bluetooth is enabled
  Future<bool> isBluetoothEnabled() async {
    return await pbt.PrintBluetoothThermal.bluetoothEnabled;
  }

  /// Get paired Bluetooth devices
  Future<List<PrinterBluetoothInfo>> getPairedDevices() async {
    bool hasPermission = await requestPermissions();
    if (!hasPermission) {
      throw Exception('Bluetooth permissions not granted');
    }

    bool isEnabled = await isBluetoothEnabled();
    if (!isEnabled) {
      throw Exception('Bluetooth is not enabled');
    }

    try {
      final List<pbt.BluetoothInfo> pairedDevices = await pbt.PrintBluetoothThermal.pairedBluetooths;
      return pairedDevices.map((device) => PrinterBluetoothInfo(
        name: device.name,
        macAdress: device.macAdress,
      )).toList();
    } catch (e) {
      debugPrint('Error getting paired devices: $e');
      return [];
    }
  }

  /// Connect to a Bluetooth printer
  Future<bool> connectToPrinter(PrinterBluetoothInfo device) async {
    try {
      bool connected = await pbt.PrintBluetoothThermal.connect(macPrinterAddress: device.macAdress);
      if (connected) {
        _connectedDevice = device;
      }
      return connected;
    } catch (e) {
      debugPrint('Error connecting to printer: $e');
      return false;
    }
  }

  /// Disconnect from the current printer
  Future<bool> disconnect() async {
    try {
      bool disconnected = await pbt.PrintBluetoothThermal.disconnect;
      if (disconnected) {
        _connectedDevice = null;
      }
      return disconnected;
    } catch (e) {
      debugPrint('Error disconnecting: $e');
      return false;
    }
  }

  /// Check if printer is connected
  Future<bool> get isConnected async => await pbt.PrintBluetoothThermal.connectionStatus;

  /// Get connected device info
  PrinterBluetoothInfo? get connectedDevice => _connectedDevice;

  /// Print image from widget
  Future<bool> printWidget(Widget widget, {
    double width = 576, // 80mm printer width in pixels (ESC/POS mm80 ~576 dots)
    double height = 800,
  }) async {
    bool connected = await isConnected;
    if (!connected) {
      throw Exception('No printer connected');
    }

    try {
      // Convert widget to image
      Uint8List? imageBytes = await _widgetToImage(widget, width, height);
      if (imageBytes == null) {
        throw Exception('Failed to convert widget to image');
      }

      // Print the image
      return await printImage(imageBytes);
    } catch (e) {
      debugPrint('Error printing widget: $e');
      return false;
    }
  }

  /// Print image bytes
  Future<bool> printImage(Uint8List imageBytes) async {
    bool connected = await isConnected;
    if (!connected) {
      throw Exception('No printer connected');
    }

    try {
      // Decode image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Resize image to fit 80mm printer (approx 576 pixels width for ESC/POS mm80)
      img.Image resizedImage = img.copyResize(image, width: 576);

      // Convert to grayscale for better printing
      img.Image grayscaleImage = img.grayscale(resizedImage);

      // Create ESC/POS commands
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      // Add image to print data
      bytes += generator.imageRaster(grayscaleImage);
      bytes += generator.feed(2);
      bytes += generator.cut();

      // Send to printer
      bool result = await pbt.PrintBluetoothThermal.writeBytes(bytes);
      return result;
    } catch (e) {
      debugPrint('Error printing image: $e');
      return false;
    }
  }

  /// Convert widget to image bytes
  Future<Uint8List?> _widgetToImage(Widget widget, double width, double height) async {
    try {
      // Create a RepaintBoundary
      final RenderRepaintBoundary repaintBoundary = RenderRepaintBoundary();
      
      // Create a pipeline owner
      final PipelineOwner pipelineOwner = PipelineOwner();
      
      // Create a build owner
      final BuildOwner buildOwner = BuildOwner(focusManager: FocusManager());

      // Create element
      final RenderObjectToWidgetElement<RenderBox> rootElement =
          RenderObjectToWidgetAdapter<RenderBox>(
        container: repaintBoundary,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Material(
              child: widget,
            ),
          ),
        ),
      ).createElement();

      // Build and layout
      rootElement.mount(null, null);
      buildOwner.buildScope(rootElement);
      buildOwner.finalizeTree();

      pipelineOwner.rootNode = repaintBoundary;
      repaintBoundary.scheduleInitialLayout();
      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      pipelineOwner.flushPaint();

      // Convert to image
      final ui.Image image = await repaintBoundary.toImage(pixelRatio: 1.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error converting widget to image: $e');
      return null;
    }
  }

  /// Print image from file path
  Future<bool> printImageFromPath(String imagePath) async {
    bool connected = await isConnected;
    if (!connected) {
      throw Exception('No printer connected');
    }

    try {
      // Read image file
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Image file not found');
      }

      Uint8List imageBytes = await file.readAsBytes();
      return await printImage(imageBytes);
    } catch (e) {
      debugPrint('Error printing image from path: $e');
      return false;
    }
  }

  /// Print text
  Future<bool> printText(String text, {int size = 1}) async {
    bool connected = await isConnected;
    if (!connected) {
      throw Exception('No printer connected');
    }

    try {
        bool result = await pbt.PrintBluetoothThermal.writeString(
          printText: pbt.PrintTextSize(size: size, text: text)
        );
        return result;
      } catch (e) {
      debugPrint('Error printing text: $e');
      return false;
    }
  }
}