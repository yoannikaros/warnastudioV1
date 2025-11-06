import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../services/bluetooth_printer_service.dart';
import '../widgets/bluetooth_printer_dialog.dart';

class PhotoShapeDisplayPage extends StatefulWidget {
  final String templateName;
  final String originalImagePath;
  final List<String> capturedPhotos;
  final List<Map<String, dynamic>> shapes;

  const PhotoShapeDisplayPage({
    super.key,
    required this.templateName,
    required this.originalImagePath,
    required this.capturedPhotos,
    required this.shapes,
  });

  @override
  State<PhotoShapeDisplayPage> createState() => _PhotoShapeDisplayPageState();
}

class _PhotoShapeDisplayPageState extends State<PhotoShapeDisplayPage> {
  ui.Image? _originalImage;
  final List<ui.Image> _capturedImages = [];
  bool _isLoading = true;
  final BluetoothPrinterService _printerService = BluetoothPrinterService();
  final GlobalKey _printKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      // Load original template image
      final File originalFile = File(widget.originalImagePath);
      if (await originalFile.exists()) {
        final Uint8List originalBytes = await originalFile.readAsBytes();
        _originalImage = await decodeImageFromList(originalBytes);
      }

      // Load captured photos
      for (String photoPath in widget.capturedPhotos) {
        final File photoFile = File(photoPath);
        if (await photoFile.exists()) {
          final Uint8List photoBytes = await photoFile.readAsBytes();
          final ui.Image image = await decodeImageFromList(photoBytes);
          _capturedImages.add(image);
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading images: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F5), // Soft cream background to match TemplateGalleryPage
      appBar: AppBar(
        title: Text(
          'Hasil - ${widget.templateName}',
          style: const TextStyle(
            color: Color(0xFF8B7355),
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: const Color(0xFFFDF8F5),
        foregroundColor: const Color(0xFF8B7355),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFB8956A)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8D5C4).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.print_rounded),
              onPressed: _showPrintDialog,
              tooltip: 'Print via Bluetooth',
              color: const Color(0xFFB8956A),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8D5C4).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.save_rounded),
              onPressed: _saveCompositeImage,
              tooltip: 'Simpan hasil',
              color: const Color(0xFFB8956A),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8D5C4).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.share_rounded),
              onPressed: _shareResult,
              tooltip: 'Bagikan',
              color: const Color(0xFFB8956A),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB8956A)),
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Memuat gambar...',
                    style: TextStyle(
                      color: Color(0xFF8B7355),
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            )
          : Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: RepaintBoundary(
                  key: _printKey,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: _originalImage != null 
                          ? _originalImage!.width / _originalImage!.height 
                          : 1.0,
                      child: CustomPaint(
                        painter: CompositeImagePainter(
                          originalImage: _originalImage,
                          capturedImages: _capturedImages,
                          shapes: widget.shapes,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    
    );
  }

  void _saveCompositeImage() {
    // TODO: Implement save functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Fitur simpan akan segera tersedia'),
        backgroundColor: const Color(0xFFB8956A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _shareResult() {
    // TODO: Implement share functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Fitur bagikan akan segera tersedia'),
        backgroundColor: const Color(0xFFB8956A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> _showPrintDialog() async {
    bool isConnected = await _printerService.isConnected;
    
    if (!mounted) return;
    
    if (isConnected) {
      // If already connected, show confirmation dialog
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text(
              'Print via Bluetooth',
              style: TextStyle(
                color: Color(0xFF8B7355),
                fontWeight: FontWeight.w600,
              ),
            ),
            content: Text(
              'Printer terhubung: ${_printerService.connectedDevice?.name ?? "Unknown"}\n\nApakah Anda ingin mencetak hasil ini?',
              style: const TextStyle(color: Color(0xFF8B7355)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Batal',
                  style: TextStyle(color: Color(0xFF8B7355)),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _printViaBluetooth();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB8956A),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Print'),
              ),
            ],
          );
        },
      );
    } else {
      // Show printer selection dialog
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return BluetoothPrinterDialog(
            onDeviceSelected: (device) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Terhubung ke ${device.name}'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
                // Auto print after connection
                Future.delayed(const Duration(milliseconds: 500), () {
                  _printViaBluetooth();
                });
              }
            },
          );
        },
      );
    }
  }

  Future<void> _printViaBluetooth() async {
    try {
      // Capture the widget as an image
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Print the image
      bool success = await _printerService.printImage(pngBytes);
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Print successful!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Print failed!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }
}

class CompositeImagePainter extends CustomPainter {
  final ui.Image? originalImage;
  final List<ui.Image> capturedImages;
  final List<Map<String, dynamic>> shapes;

  CompositeImagePainter({
    required this.originalImage,
    required this.capturedImages,
    required this.shapes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (originalImage == null) return;

    final Paint paint = Paint();
    
    // Draw captured photos in shapes first (background layer)
    for (int i = 0; i < shapes.length && i < capturedImages.length; i++) {
      final shape = shapes[i];
      final capturedImage = capturedImages[i];
      
      // Get normalized coordinates
      final double normalizedX = (shape['normalized_x'] as num).toDouble();
      final double normalizedY = (shape['normalized_y'] as num).toDouble();
      final double normalizedWidth = (shape['normalized_width'] as num).toDouble();
      final double normalizedHeight = (shape['normalized_height'] as num).toDouble();
      
      // Convert to actual coordinates
      final double x = normalizedX * size.width;
      final double y = normalizedY * size.height;
      final double width = normalizedWidth * size.width;
      final double height = normalizedHeight * size.height;
      
      final Rect shapeRect = Rect.fromLTWH(x, y, width, height);
      
      // Calculate crop area to maintain aspect ratio and fill the shape
      final double imageWidth = capturedImage.width.toDouble();
      final double imageHeight = capturedImage.height.toDouble();
      final double shapeAspectRatio = width / height;
      final double imageAspectRatio = imageWidth / imageHeight;
      
      Rect sourceRect;
      
      if (imageAspectRatio > shapeAspectRatio) {
        // Image is wider than shape - crop horizontally (center crop)
        final double cropWidth = imageHeight * shapeAspectRatio;
        final double cropX = (imageWidth - cropWidth) / 2;
        sourceRect = Rect.fromLTWH(cropX, 0, cropWidth, imageHeight);
      } else {
        // Image is taller than shape - crop vertically (center crop)
        final double cropHeight = imageWidth / shapeAspectRatio;
        final double cropY = (imageHeight - cropHeight) / 2;
        sourceRect = Rect.fromLTWH(0, cropY, imageWidth, cropHeight);
      }
      
      // Draw captured photo in the shape area
      canvas.save();
      
      if (shape['shape_type'] == 'circle') {
        // Clip to circle
        canvas.clipPath(Path()..addOval(shapeRect));
      } else {
        // Clip to rectangle
        canvas.clipRect(shapeRect);
      }
      
      // Draw the cropped image
      canvas.drawImageRect(
        capturedImage,
        sourceRect,
        shapeRect,
        paint,
      );
      
      canvas.restore();
    }
    
    // Draw original image on top (foreground layer)
    final Rect imageRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      originalImage!,
      Rect.fromLTWH(0, 0, originalImage!.width.toDouble(), originalImage!.height.toDouble()),
      imageRect,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}