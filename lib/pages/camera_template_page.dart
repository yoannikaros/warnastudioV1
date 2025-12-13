import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'manual_segmentation_page.dart';
import 'camera_template_reverse_page.dart';
import '../helpers/database_helper.dart';

class CompositeImagePainter extends CustomPainter {
  final ui.Image originalImage;
  final List<ui.Image> capturedImages;
  final List<Map<String, dynamic>> shapes;

  CompositeImagePainter({
    required this.originalImage,
    required this.capturedImages,
    required this.shapes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Draw captured images as background first
    if (capturedImages.isNotEmpty && shapes.isNotEmpty) {
      for (int i = 0; i < shapes.length && i < capturedImages.length; i++) {
        final shape = shapes[i];
        final capturedImage =
            capturedImages[0]; // Use first captured image for all shapes

        // Calculate shape position and size relative to canvas
        final normalizedX = shape['normalized_x'] ?? 0.0;
        final normalizedY = shape['normalized_y'] ?? 0.0;
        final normalizedWidth = shape['normalized_width'] ?? 0.0;
        final normalizedHeight = shape['normalized_height'] ?? 0.0;

        final shapeRect = Rect.fromLTWH(
          normalizedX * size.width,
          normalizedY * size.height,
          normalizedWidth * size.width,
          normalizedHeight * size.height,
        );

        // Create clipping path based on shape type
        final shapeType = shape['shape_type'] ?? 'rectangle';
        canvas.save();

        if (shapeType == 'rectangle') {
          canvas.clipRect(shapeRect);
        } else if (shapeType == 'ellipse') {
          canvas.clipPath(Path()..addOval(shapeRect));
        }

        // Draw captured image within the clipped area
        canvas.drawImageRect(
          capturedImage,
          Rect.fromLTWH(
            0,
            0,
            capturedImage.width.toDouble(),
            capturedImage.height.toDouble(),
          ),
          shapeRect,
          paint,
        );

        canvas.restore();
      }
    }

    // Draw template image on top
    final originalRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      originalImage,
      Rect.fromLTWH(
        0,
        0,
        originalImage.width.toDouble(),
        originalImage.height.toDouble(),
      ),
      originalRect,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class TemplateOverlayPainter extends CustomPainter {
  final ui.Image originalImage;

  TemplateOverlayPainter({required this.originalImage});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Draw template image
    final originalRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      originalImage,
      Rect.fromLTWH(
        0,
        0,
        originalImage.width.toDouble(),
        originalImage.height.toDouble(),
      ),
      originalRect,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class CameraTemplatePage extends StatefulWidget {
  final String? templateName;
  final String? originalImagePath;
  final List<Map<String, dynamic>>? shapes;

  const CameraTemplatePage({
    super.key,
    this.templateName,
    this.originalImagePath,
    this.shapes,
  });

  @override
  State<CameraTemplatePage> createState() => _CameraTemplatePageState();
}

class _CameraTemplatePageState extends State<CameraTemplatePage> {
  CameraController? _controller;
  // Hapus _secondController karena akan menggunakan satu controller untuk kedua preview
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCountingDown = false;
  int _countdown = 5;
  Timer? _navigationTimer;

  // Template data
  String? _originalImagePath;
  ui.Image? _originalImage;
  bool _isLoadingTemplate = true;

  // Camera error handling
  bool _isCameraInitializing = true;
  String? _cameraError;
  int _cameraRetryCount = 0;
  static const int _maxRetryAttempts = 3;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    // Set landscape orientation when page loads
    SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,

    ]);
    _initializeTemplate();
    _initializeCamera();
  }

  Future<void> _initializeTemplate() async {
    try {
      // Use provided template data or load default
      if (widget.templateName != null && widget.originalImagePath != null) {
        _originalImagePath = widget.originalImagePath;
      } else {
        // Load default template
        await DatabaseHelper.insertDefaultTemplate();
        final templates = await ShapeDatabase.instance.getAllTemplates();
        final defaultTemplate = templates.firstWhere(
          (t) => t.name == 'default',
          orElse: () => templates.first,
        );

        _originalImagePath = defaultTemplate.imagePath;
      }

      // Load template image
      if (_originalImagePath != null) {
        await _loadTemplateImage();
      }

      setState(() {
        _isLoadingTemplate = false;
      });
    } catch (e) {
      debugPrint('Error initializing template: $e');
      setState(() {
        _isLoadingTemplate = false;
      });
    }
  }

  Future<void> _loadTemplateImage() async {
    try {
      Uint8List bytes;

      // Check if it's an asset path or file path
      if (_originalImagePath!.startsWith('assets/')) {
        // Load from assets
        final ByteData data = await rootBundle.load(_originalImagePath!);
        bytes = data.buffer.asUint8List();
      } else {
        // Load from file system
        final file = File(_originalImagePath!);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        } else {
          debugPrint('Template image file not found: $_originalImagePath');
          return;
        }
      }

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      setState(() {
        _originalImage = frame.image;
      });
    } catch (e) {
      debugPrint('Error loading template image: $e');
    }
  }

  Future<void> _initializeCamera() async {
    // Ensure landscape orientation before camera initialization
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    setState(() {
      _isCameraInitializing = true;
      _cameraError = null;
    });

    try {
      debugPrint(
        'Attempting to initialize camera (attempt ${_cameraRetryCount + 1}/$_maxRetryAttempts)',
      );

      // Add delay to ensure proper cleanup from previous page
      await Future.delayed(const Duration(milliseconds: 500));

      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('Tidak ada kamera yang tersedia pada perangkat ini');
      }

      // Cari kamera depan
      CameraDescription? frontCamera;

      for (var camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }

      // Gunakan kamera depan, atau kamera pertama jika tidak ada kamera depan
      final selectedCamera = frontCamera ?? _cameras!.first;

      // Dispose previous controller if exists
      await _controller?.dispose();

      // Inisialisasi satu kamera controller untuk kedua preview
      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isCameraInitializing = false;
          _cameraError = null;
          _cameraRetryCount = 0; // Reset retry count on success
        });

        // Ensure landscape orientation after camera initialization
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);

        // Debug info
        debugPrint(
          'Camera initialized successfully: ${selectedCamera.lensDirection} - ${selectedCamera.name}',
        );
        debugPrint('Satu kamera akan digunakan untuk kedua kolom');

        // Add small delay before starting countdown to ensure UI is ready
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _isInitialized) {
            _startCountdown();
          }
        });
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');

      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _cameraError = _getCameraErrorMessage(e);
        });

        // Retry logic
        if (_cameraRetryCount < _maxRetryAttempts) {
          _cameraRetryCount++;
          debugPrint(
            'Retrying camera initialization in 2 seconds... (attempt $_cameraRetryCount/$_maxRetryAttempts)',
          );

          _retryTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) {
              _initializeCamera();
            }
          });
        } else {
          debugPrint(
            'Max retry attempts reached. Camera initialization failed.',
          );
        }
      }
    }
  }

  String _getCameraErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('permission')) {
      return 'Izin kamera diperlukan untuk menggunakan fitur ini.\nSilakan berikan izin kamera di pengaturan aplikasi.';
    } else if (errorString.contains('not available') ||
        errorString.contains('tidak tersedia')) {
      return 'Kamera tidak tersedia pada perangkat ini.\nPastikan kamera tidak sedang digunakan aplikasi lain.';
    } else if (errorString.contains('busy') || errorString.contains('in use')) {
      return 'Kamera sedang digunakan aplikasi lain.\nTutup aplikasi lain yang menggunakan kamera.';
    } else if (errorString.contains('timeout')) {
      return 'Waktu inisialisasi kamera habis.\nCoba lagi dalam beberapa saat.';
    } else {
      return 'Terjadi masalah saat mengakses kamera.\nCoba restart aplikasi atau perangkat Anda.';
    }
  }

  Future<void> _retryCamera() async {
    _cameraRetryCount = 0; // Reset retry count for manual retry
    await _initializeCamera();
  }

  Future<void> _startCountdown() async {
    if (_isCountingDown) return;

    setState(() {
      _isCountingDown = true;
      _countdown = 5;
    });

    for (int i = 5; i > 0; i--) {
      if (!mounted) return;
      setState(() {
        _countdown = i;
      });

      // Only delay if not the last iteration
      if (i > 1) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // Immediately capture photo after countdown reaches 1
    if (mounted) {
      await _capturePhoto();
    }
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final image = await _controller!.takePicture();
      final directory = await getApplicationDocumentsDirectory();
      final imagePath =
          '${directory.path}/captured_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(image.path).copy(imagePath);

      if (mounted) {
        setState(() {
          _isCountingDown = false;
        });

        // Navigate immediately to CameraTemplateReversePage with captured photo
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (context) => CameraTemplateReversePage(
                  templateName: widget.templateName,
                  originalImagePath: widget.originalImagePath,
                  shapes: widget.shapes,
                  capturedImagePath: imagePath, // Pass the captured photo
                ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error capturing photo: $e');
      if (mounted) {
        setState(() {
          _isCountingDown = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _retryTimer?.cancel();
    _controller?.dispose();
    // Reset orientation when leaving page
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ensure landscape orientation during build
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // decoration: const BoxDecoration(
        //   image: DecorationImage(
        //     image: AssetImage('assets/images/bg.png'),
        //     fit: BoxFit.cover,
        //     alignment: Alignment.center,
        //   ),
        // ),
        child: SafeArea(
          child: Stack(
            children: [
              // Main content
              LayoutBuilder(
                builder: (context, constraints) {
                  final screenWidth = constraints.maxWidth;
                  final screenHeight = constraints.maxHeight;
                  final isLandscape = screenWidth > screenHeight;

                  return Row(
                    children: [
                      // Bagian Kiri - Kamera
                      Expanded(
                        flex: 1,
                        child: Container(
                          margin: EdgeInsets.all(isLandscape ? 16 : 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: _buildCameraPreview(),
                          ),
                        ),
                      ),
                      // Bagian Kanan - Template Display
                      Expanded(
                        flex: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _buildTemplateDisplay(),
                        ),
                      ),
                    ], // End of Row children
                  );
                },
              ), // End of LayoutBuilder
              // Logo positioned at top-left
              Positioned(
                top: 30,
                left: 25,
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 50,
                  width: 50,
                  fit: BoxFit.contain,
                ),
              ),
            ], // End of Stack children
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    // Show loading state while initializing
    if (_isCameraInitializing) {
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Color(0xFFB8956A),
                strokeWidth: 3,
              ),
              SizedBox(height: 16),
              Text(
                'Menginisialisasi Kamera...',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8B7355),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show error state with retry option
    if (_cameraError != null) {
      return Container(
        color: Colors.grey[100],
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Kamera Tidak Tersedia',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8B7355),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _retryCamera,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: Text(
                  'Coba Lagi',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB8956A),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show camera preview
    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Color(0xFFB8956A),
                strokeWidth: 3,
              ),
              SizedBox(height: 16),
              Text(
                'Memuat Kamera...',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8B7355),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: CameraPreview(_controller!),
          ),
        ),

        // Countdown overlay - hanya menutupi area kamera
        if (_isCountingDown)
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _countdown.toString(),
                        style: GoogleFonts.jersey10(
                          fontSize: 120,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Get Ready!',
                        style: GoogleFonts.jersey10(
                          fontSize: 24,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTemplateDisplay() {
    if (_isLoadingTemplate) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFB8956A), strokeWidth: 3),
            SizedBox(height: 12),
            Text(
              'Memuat template...',
              style: TextStyle(color: Color(0xFF8B7355), fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Template preview dengan ukuran yang proporsional
    return Column(
      children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: 3 / 4, // Rasio 3:4 untuk ukuran yang lebih normal
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child:
                    _originalImage != null &&
                            _controller != null &&
                            _isInitialized &&
                            _cameraError == null
                        ? Stack(
                          children: [
                            // Live camera feed sebagai background (menggunakan controller yang sama)
                            Positioned.fill(
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: _controller!.value.aspectRatio,
                                  child: CameraPreview(_controller!),
                                ),
                              ),
                            ),
                            // Template overlay di atas camera feed
                            Positioned.fill(
                              child: CustomPaint(
                                painter: TemplateOverlayPainter(
                                  originalImage: _originalImage!,
                                ),
                              ),
                            ),
                          ],
                        )
                        : Container(
                          color: const Color(0xFFF5F5F5),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _cameraError != null
                                      ? Icons.camera_alt_outlined
                                      : Icons.hourglass_empty,
                                  size: 48,
                                  color: const Color(0xFFB8956A),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _cameraError != null
                                      ? 'Kamera tidak tersedia'
                                      : 'Memuat preview...',
                                  style: const TextStyle(
                                    color: Color(0xFF8B7355),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
