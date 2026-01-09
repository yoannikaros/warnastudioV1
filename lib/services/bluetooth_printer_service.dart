import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart' as pbt;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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

      // Adjust brightness - make it brighter for better thermal printing
      // Brightness range: -255 to 255, we use +30 for slightly brighter
      grayscaleImage = img.adjustColor(grayscaleImage, brightness: 30);

      // Adjust contrast - enhance details
      // Contrast range: 0.0 to infinity, 1.0 is normal, we use 1.2 for better contrast
      grayscaleImage = img.adjustColor(grayscaleImage, contrast: 1.2);

      // Apply dithering for better greyscale representation on thermal printer
      // Thermal printers only print black or white, dithering creates the illusion of grey
      grayscaleImage = img.ditherImage(
        grayscaleImage,
        kernel: img.DitherKernel.floydSteinberg,
      );

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

  /// Generate PDF preview of the print image (with all print adjustments applied)
  /// Returns the processed image bytes that will be printed
  Future<Uint8List?> generatePdfPreview(Uint8List imageBytes) async {
    try {
      debugPrint('=== generatePdfPreview START ===');
      debugPrint('Input bytes length: ${imageBytes.length}');

      // Validate input
      if (imageBytes.isEmpty) {
        debugPrint('ERROR: Empty image bytes');
        return null;
      }

      // TEMPORARY: Skip processing and return original to test
      debugPrint('BYPASSING PROCESSING - returning original bytes for testing');
      debugPrint('=== generatePdfPreview END (BYPASSED) ===');
      return imageBytes;

      /* ORIGINAL PROCESSING CODE - TEMPORARILY DISABLED
      // Decode image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        debugPrint('ERROR: Failed to decode image');
        return null;
      }
      debugPrint('Decoded image: ${image.width}x${image.height}');

      // Validate decoded image
      if (image.width == 0 || image.height == 0) {
        debugPrint('ERROR: Invalid image dimensions');
        return null;
      }

      // Resize image to fit 80mm printer (approx 576 pixels width for ESC/POS mm80)
      img.Image processedImage = img.copyResize(image, width: 576);
      debugPrint('Resized: ${processedImage.width}x${processedImage.height}');

      // Convert to grayscale for better printing
      processedImage = img.grayscale(processedImage);
      debugPrint('Applied grayscale');
      
      // Validate after grayscale
      if (processedImage.width == 0 || processedImage.height == 0) {
        debugPrint('ERROR: Image corrupted after grayscale');
        return null;
      }

      // Adjust brightness - make it brighter for better thermal printing
      processedImage = img.adjustColor(processedImage, brightness: 30);
      debugPrint('Applied brightness');

      // Adjust contrast - enhance details
      processedImage = img.adjustColor(processedImage, contrast: 1.2);
      debugPrint('Applied contrast');

      // Apply dithering for better greyscale representation on thermal printer
      processedImage = img.ditherImage(
        processedImage,
        kernel: img.DitherKernel.floydSteinberg,
      );
      debugPrint('Applied dithering');
      
      // Validate final image
      if (processedImage.width == 0 || processedImage.height == 0) {
        debugPrint('ERROR: Image corrupted after processing');
        return null;
      }

      // Encode back to PNG
      List<int> pngBytes = img.encodePng(processedImage);
      if (pngBytes.isEmpty) {
        debugPrint('ERROR: Failed to encode PNG');
        return null;
      }
      
      final result = Uint8List.fromList(pngBytes);
      debugPrint('Encoded PNG: ${result.length} bytes');
      debugPrint('Final image: ${processedImage.width}x${processedImage.height}');
      debugPrint('=== generatePdfPreview END (SUCCESS) ===');
      return result;
      */
    } catch (e, stackTrace) {
      debugPrint('ERROR in generatePdfPreview: $e');
      debugPrint('StackTrace: $stackTrace');
      return null;
    }
  }

  /// Show image preview of how the image will be printed (replaces PDF preview)
  Future<void> showImagePreview(
    BuildContext context,
    Uint8List imageBytes,
  ) async {
    try {
      debugPrint('=== showImagePreview START ===');
      debugPrint('Input imageBytes length: ${imageBytes.length}');

      final processedImage = await generatePdfPreview(imageBytes);

      bool isProcessed = false;
      Uint8List displayImage;

      if (processedImage == null || processedImage.isEmpty) {
        debugPrint('WARNING: processedImage is null/empty, showing original');
        displayImage = imageBytes;
        isProcessed = false;
      } else {
        debugPrint('SUCCESS: Using processed image');
        displayImage = processedImage;
        isProcessed = true;
      }

      debugPrint('Display image length: ${displayImage.length}');
      debugPrint('Is processed: $isProcessed');

      // Show preview in a dialog
      if (!context.mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          // Capture variables in builder scope
          final Uint8List imageToDisplay = displayImage;
          final bool showAsProcessed = isProcessed;

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.preview,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            showAsProcessed
                                ? 'Preview Hasil Print'
                                : 'Preview (Original)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),

                  // Image preview
                  Flexible(
                    child: SingleChildScrollView(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!showAsProcessed)
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Processing gagal, menampilkan gambar original',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (showAsProcessed) ...[
                              const Text(
                                'Gambar ini sudah diproses dengan:',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildProcessChip('Brightness +30'),
                                  const SizedBox(width: 8),
                                  _buildProcessChip('Contrast 1.2x'),
                                  const SizedBox(width: 8),
                                  _buildProcessChip('Dithering'),
                                ],
                              ),
                              const SizedBox(height: 20),
                            ],
                            Container(
                              constraints: const BoxConstraints(maxHeight: 500),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.grey.shade50,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  imageToDisplay,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                  errorBuilder: (context, error, stackTrace) {
                                    debugPrint('=== IMAGE DISPLAY ERROR ===');
                                    debugPrint('Error: $error');
                                    debugPrint(
                                      'Bytes length: ${imageToDisplay.length}',
                                    );
                                    debugPrint('StackTrace: $stackTrace');
                                    return Container(
                                      padding: const EdgeInsets.all(40),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.error_outline,
                                            color: Colors.red,
                                            size: 64,
                                          ),
                                          const SizedBox(height: 24),
                                          const Text(
                                            'Gagal menampilkan gambar',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Bytes: ${imageToDisplay.length}\nError: $error',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.red.shade700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              showAsProcessed
                                  ? 'Ini adalah hasil yang akan dicetak ke thermal printer'
                                  : 'Debug: ${imageToDisplay.length} bytes',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black45,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e, stackTrace) {
      debugPrint('=== ERROR in showImagePreview ===');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Helper widget for process chips
  static Widget _buildProcessChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4CAF50), width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF4CAF50),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Generate and save PDF from composite image bytes
  Future<bool> generateAndSavePdf(
    BuildContext context,
    Uint8List imageBytes, {
    String defaultFileName = 'warna_studio_photo',
  }) async {
    try {
      debugPrint('=== generateAndSavePdf START ===');
      debugPrint('Image bytes length: ${imageBytes.length}');
      debugPrint('Platform: ${Platform.operatingSystem}');

      // Create PDF document
      final pdf = pw.Document();

      // Convert bytes to PDF image
      final pdfImage = pw.MemoryImage(imageBytes);

      // Add page with image
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain));
          },
        ),
      );

      debugPrint('PDF document created');

      // Generate PDF bytes
      final pdfBytes = await pdf.save();
      debugPrint('PDF bytes generated: ${pdfBytes.length} bytes');

      String? outputPath;
      File? savedFile;

      // Handle differently for mobile vs desktop
      if (Platform.isAndroid || Platform.isIOS) {
        // Mobile: Save directly to app documents directory
        debugPrint('Mobile platform detected - saving to app documents');

        final directory = await getApplicationDocumentsDirectory();
        final fileName =
            '${defaultFileName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        outputPath = '${directory.path}/$fileName';

        savedFile = File(outputPath);
        await savedFile.writeAsBytes(pdfBytes);

        debugPrint('PDF saved to: $outputPath');
      } else {
        // Desktop: Use file picker dialog
        debugPrint('Desktop platform detected - using file picker');

        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan PDF',
          fileName: '$defaultFileName.pdf',
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          bytes: pdfBytes, // Provide bytes for desktop too
        );

        if (outputPath == null) {
          debugPrint('User cancelled save dialog');
          return false;
        }

        // Ensure .pdf extension
        if (!outputPath.toLowerCase().endsWith('.pdf')) {
          outputPath = '$outputPath.pdf';
        }

        debugPrint('Saving to: $outputPath');

        // Save PDF file
        savedFile = File(outputPath);
        await savedFile.writeAsBytes(pdfBytes);
      }

      debugPrint('PDF saved successfully: ${savedFile.path}');
      debugPrint('=== generateAndSavePdf END (SUCCESS) ===');

      // Show success message
      if (context.mounted) {
        final fileName = path.basename(outputPath);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Platform.isAndroid || Platform.isIOS
                  ? 'PDF berhasil disimpan: $fileName'
                  : 'PDF berhasil disimpan ke: $fileName',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action:
                (Platform.isAndroid || Platform.isIOS)
                    ? null // No folder opening on mobile
                    : SnackBarAction(
                      label: 'Buka Folder',
                      textColor: Colors.white,
                      onPressed: () async {
                        // Open file location (desktop only)
                        final directory = path.dirname(outputPath!);
                        try {
                          if (Platform.isWindows) {
                            await Process.run('explorer', [directory]);
                          } else if (Platform.isMacOS) {
                            await Process.run('open', [directory]);
                          } else if (Platform.isLinux) {
                            await Process.run('xdg-open', [directory]);
                          }
                        } catch (e) {
                          debugPrint('Error opening folder: $e');
                        }
                      },
                    ),
          ),
        );
      }

      return true;
    } catch (e, stackTrace) {
      debugPrint('=== ERROR in generateAndSavePdf ===');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan PDF: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      return false;
    }
  }
}
