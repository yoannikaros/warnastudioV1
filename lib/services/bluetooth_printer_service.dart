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

  PrinterBluetoothInfo({required this.name, required this.macAdress});
}

class BluetoothPrinterService {
  static final BluetoothPrinterService _instance =
      BluetoothPrinterService._internal();
  factory BluetoothPrinterService() => _instance;
  BluetoothPrinterService._internal();

  PrinterBluetoothInfo? _connectedDevice;

  /// Request necessary permissions for Bluetooth
  Future<bool> requestPermissions() async {
    // Check if Bluetooth permission is granted
    bool isGranted =
        await pbt.PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!isGranted) {
      // Request location permission for older Android versions
      Map<Permission, PermissionStatus> statuses =
          await [
            Permission.location,
            Permission.bluetooth,
            Permission.bluetoothScan,
            Permission.bluetoothConnect,
          ].request();

      return statuses.values.any(
        (status) =>
            status == PermissionStatus.granted ||
            status == PermissionStatus.limited,
      );
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
      final List<pbt.BluetoothInfo> pairedDevices =
          await pbt.PrintBluetoothThermal.pairedBluetooths;
      return pairedDevices
          .map(
            (device) => PrinterBluetoothInfo(
              name: device.name,
              macAdress: device.macAdress,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('Error getting paired devices: $e');
      return [];
    }
  }

  /// Connect to a Bluetooth printer
  Future<bool> connectToPrinter(PrinterBluetoothInfo device) async {
    try {
      bool connected = await pbt.PrintBluetoothThermal.connect(
        macPrinterAddress: device.macAdress,
      );
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
  Future<bool> get isConnected async =>
      await pbt.PrintBluetoothThermal.connectionStatus;

  /// Get connected device info
  PrinterBluetoothInfo? get connectedDevice => _connectedDevice;

  /// Print image from widget
  Future<bool> printWidget(
    Widget widget, {
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

  /// Print image bytes with dithering for grayscale simulation
  Future<bool> printImage(
    Uint8List imageBytes, {
    bool useDithering = true,
  }) async {
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

      // Resize only if image is too wide for the printer
      // 80mm thermal printer: 576 dots max width
      const int printerWidth = 576;
      if (image.width > printerWidth) {
        // Downscale to fit printer width while maintaining aspect ratio
        image = img.copyResize(
          image,
          width: printerWidth,
          interpolation: img.Interpolation.cubic,
        );
      }
      // Don't upscale smaller images - keeps original quality

      // Convert to grayscale
      image = img.grayscale(image);

      // Enhance image quality before dithering
      image = _preprocessImageForPrinting(image);

      // Apply dithering for better grayscale simulation
      if (useDithering) {
        image = _applyAtkinsonDithering(image);
      }

      // Generate ESC/POS commands for the image
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      // Use imageRaster with high density settings for better resolution
      // This is more reliable than graphics mode
      bytes += generator.imageRaster(
        image,
        align: PosAlign.center,
        highDensityHorizontal: true,
        highDensityVertical: true,
      );

      // Add line feed and paper cut
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

  /// Preprocess image for better print quality
  img.Image _preprocessImageForPrinting(img.Image image) {
    // Adjust contrast and brightness for better detail
    image = img.adjustColor(
      image,
      contrast: 1,
      brightness: 1.2, // Slight brightness increase
    );

    // Sharpen slightly to enhance details
    // image = img.gaussianBlur(image, radius: 1); // Slight blur to reduce noise

    return image;
  }

  /// Apply Atkinson dithering - better for photos than Floyd-Steinberg
  /// Produces lighter, more natural-looking results
  img.Image _applyAtkinsonDithering(img.Image image) {
    final img.Image dithered = img.Image.from(image);

    for (int y = 0; y < dithered.height; y++) {
      for (int x = 0; x < dithered.width; x++) {
        final oldPixel = dithered.getPixel(x, y);
        final oldValue = oldPixel.r.toInt();

        // Quantize to black or white
        final newValue = oldValue < 128 ? 0 : 255;
        dithered.setPixel(x, y, img.ColorRgb8(newValue, newValue, newValue));

        // Calculate error
        final error = oldValue - newValue;

        // Atkinson dithering distributes error differently (1/8 to 6 neighbors)
        // Creates lighter, more aesthetic results for photos
        final errorDiv8 = error / 8;

        if (x + 1 < dithered.width) {
          _addError(dithered, x + 1, y, errorDiv8);
        }
        if (x + 2 < dithered.width) {
          _addError(dithered, x + 2, y, errorDiv8);
        }
        if (y + 1 < dithered.height) {
          if (x - 1 >= 0) {
            _addError(dithered, x - 1, y + 1, errorDiv8);
          }
          _addError(dithered, x, y + 1, errorDiv8);
          if (x + 1 < dithered.width) {
            _addError(dithered, x + 1, y + 1, errorDiv8);
          }
        }
        if (y + 2 < dithered.height) {
          _addError(dithered, x, y + 2, errorDiv8);
        }
      }
    }

    return dithered;
  }

  /// Apply Floyd-Steinberg dithering to simulate grayscale on thermal printer
  img.Image _applyFloydSteinbergDithering(img.Image image) {
    // Clone the image to avoid modifying the original
    final img.Image dithered = img.Image.from(image);

    for (int y = 0; y < dithered.height; y++) {
      for (int x = 0; x < dithered.width; x++) {
        final oldPixel = dithered.getPixel(x, y);
        final oldValue = oldPixel.r.toInt(); // Grayscale, so r = g = b

        // Quantize to black (0) or white (255)
        final newValue = oldValue < 128 ? 0 : 255;

        // Set the new pixel value
        dithered.setPixel(x, y, img.ColorRgb8(newValue, newValue, newValue));

        // Calculate quantization error
        final error = oldValue - newValue;

        // Distribute error to neighboring pixels (Floyd-Steinberg)
        if (x + 1 < dithered.width) {
          _addError(dithered, x + 1, y, error * 7 / 16);
        }
        if (y + 1 < dithered.height) {
          if (x > 0) {
            _addError(dithered, x - 1, y + 1, error * 3 / 16);
          }
          _addError(dithered, x, y + 1, error * 5 / 16);
          if (x + 1 < dithered.width) {
            _addError(dithered, x + 1, y + 1, error * 1 / 16);
          }
        }
      }
    }

    return dithered;
  }

  /// Helper method to add error to a pixel during dithering
  void _addError(img.Image image, int x, int y, double error) {
    final pixel = image.getPixel(x, y);
    final oldValue = pixel.r.toInt();
    final newValue = (oldValue + error).clamp(0, 255).toInt();
    image.setPixel(x, y, img.ColorRgb8(newValue, newValue, newValue));
  }

  /// Convert widget to image bytes
  Future<Uint8List?> _widgetToImage(
    Widget widget,
    double width,
    double height,
  ) async {
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
                child: Material(child: widget),
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
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

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
        printText: pbt.PrintTextSize(size: size, text: text),
      );
      return result;
    } catch (e) {
      debugPrint('Error printing text: $e');
      return false;
    }
  }
}
