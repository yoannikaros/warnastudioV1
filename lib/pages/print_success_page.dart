import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'landing_page.dart';
import '../services/bluetooth_printer_service.dart';
import 'camera_template_reverse_page.dart';

class PrintSuccessPage extends StatefulWidget {
  final String? capturedImagePath;
  final ui.Image? originalImage;
  final ui.Image? capturedImage;
  final List<Map<String, dynamic>>? shapes;
  final int printQuantity;

  const PrintSuccessPage({
    super.key,
    this.capturedImagePath,
    this.originalImage,
    this.capturedImage,
    this.shapes,
    required this.printQuantity,
  });

  @override
  State<PrintSuccessPage> createState() => _PrintSuccessPageState();
}

class _PrintSuccessPageState extends State<PrintSuccessPage> {
  final BluetoothPrinterService _printerService = BluetoothPrinterService();
  bool _isPrinting = true;
  int _printedCount = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startPrinting();
  }

  Future<void> _startPrinting() async {
    if (widget.capturedImagePath == null || widget.originalImage == null || widget.capturedImage == null) {
      setState(() {
        _isPrinting = false;
        _errorMessage = 'Data gambar tidak lengkap';
      });
      return;
    }

    String? compositeImagePath;

    try {
      // Create composite image
      compositeImagePath = await _createCompositeImage();

      if (compositeImagePath == null) {
        throw Exception('Gagal membuat gambar gabungan');
      }

      // Print multiple copies
      for (int i = 0; i < widget.printQuantity; i++) {
        final success = await _printerService.printImageFromPath(
          compositeImagePath,
        );

        if (success) {
          setState(() {
            _printedCount++;
          });
        }

        if (i < widget.printQuantity - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      setState(() {
        _isPrinting = false;
      });
    } catch (e) {
      debugPrint('Error during printing: $e');
      setState(() {
        _isPrinting = false;
        _errorMessage = e.toString().contains('gabungan')
            ? 'Gagal membuat gambar gabungan'
            : 'Gagal mencetak foto. Periksa koneksi printer.';
      });
    } finally {
      // Clean up composite image file
      if (compositeImagePath != null) {
        try {
          await File(compositeImagePath).delete();
        } catch (e) {
          debugPrint('Error deleting composite image: $e');
        }
      }
    }
  }

  Future<String?> _createCompositeImage() async {
    if (widget.originalImage == null || widget.capturedImage == null) {
      return null;
    }

    try {
      // Create a picture recorder to draw the composite image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Define the size for the composite image (use template size)
      const size = Size(800, 1000); // Standard print size ratio 4:5

      // Use the CapturedImageWithTemplatePainter to draw the composite
      final painter = CapturedImageWithTemplatePainter(
        templateImage: widget.originalImage!,
        capturedImage: widget.capturedImage!,
        shapes: widget.shapes,
      );

      painter.paint(canvas, size);

      // Convert to image
      final picture = recorder.endRecording();
      final img = await picture.toImage(size.width.toInt(), size.height.toInt());

      // Convert to bytes
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      // Save to file
      final directory = Directory.systemTemp;
      final compositePath = '${directory.path}/composite_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(compositePath);
      await file.writeAsBytes(bytes);

      return compositePath;
    } catch (e) {
      debugPrint('Error creating composite image: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Gradient Background with colorful blobs
          _buildGradientBackground(size),

          // Main content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon - Loading or Success/Error
                  if (_isPrinting)
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(30.0),
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          color: Colors.blue,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: _errorMessage == null
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _errorMessage == null ? Icons.check_circle : Icons.error,
                        size: 80,
                        color: _errorMessage == null ? Colors.green : Colors.red,
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Status Message
                  Text(
                    _isPrinting
                        ? 'Mencetak Foto...'
                        : (_errorMessage == null
                            ? 'Foto Berhasil Dicetak!'
                            : 'Pencetakan Gagal'),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  // Details
                  Text(
                    _isPrinting
                        ? 'Sedang mencetak $_printedCount dari ${widget.printQuantity} foto...'
                        : (_errorMessage ??
                            '${_printedCount} dari ${widget.printQuantity} foto berhasil dicetak'),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 48),

                  // Back to Home Button - Only show when printing is done
                  if (!_isPrinting)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          // Navigate back to LandingPage and clear all previous routes
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => const LandingPage(),
                            ),
                            (route) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.home, size: 24),
                            SizedBox(width: 12),
                            Text(
                              'Kembali ke Beranda',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                  
                  // Additional info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.grey.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Terima kasih telah menggunakan Photo Booth!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientBackground(Size size) {
    return Stack(
      children: [
        // Base layer - PUTIH
        Container(
          width: size.width,
          height: size.height,
          color: Colors.white,
        ),
        
        // Orange blob - KIRI ATAS (setengah keluar pinggir)
        Positioned(
          left: -size.width * 0.35, // Setengah ke kiri pinggir
          top: -size.height * -0.2,  // Setengah ke atas pinggir
          child: Container(
            width: size.width * 0.7,
            height: size.height * 0.8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0xFFFF4500),
                  Color(0xFFFF5722),
                  Color(0xFFFF6F43),
                  Color(0xFFFF8A65),
                  Color(0xFFFFAB91),
                  Colors.transparent,
                ],
                stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
              ),
            ),
          ),
        ),
        
        // Green/Lime blob - top right (DI BELAKANG BIRU)
        Positioned(
          right: -size.width * 0.15,
          top: -size.height * 0.1,
          child: Container(
            width: size.width * 0.75,
            height: size.height * 0.85,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0xFFAFB42B),
                  Color(0xFFCDDC39),
                  Color(0xFFD4E157),
                  Color(0xFFDCE775),
                  Color(0xFFE6EE9C),
                  Colors.transparent,
                ],
                stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
              ),
            ),
          ),
        ),
        
        // Blue blob - center (DI DEPAN LIME) - BIRU TUA
        Positioned(
          left: size.width * 0.25,
          top: size.height * 0.15,
          child: Container(
            width: size.width * 0.55,
            height: size.height * 0.65,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0xFF0D47A1),
                  Color(0xFF1565C0),
                  Color(0xFF1976D2),
                  Color(0xFF1E88E5),
                  Color(0xFF42A5F5),
                  Colors.transparent,
                ],
                stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
              ),
            ),
          ),
        ),
        
        // Blur effect
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 60.0, sigmaY: 60.0),
          child: Container(
            color: Colors.transparent,
          ),
        ),
      ],
    );
  }
}