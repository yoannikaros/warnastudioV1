import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:permission_handler/permission_handler.dart';
import 'manual_segmentation_page.dart';
import '../helpers/database_helper.dart';
import '../services/bluetooth_printer_service.dart';
import '../widgets/bluetooth_printer_dialog.dart';
import 'print_success_page.dart';

class CapturedImageWithTemplatePainter extends CustomPainter {
  final ui.Image templateImage;
  final ui.Image? capturedImage;
  final List<Map<String, dynamic>>? shapes;

  CapturedImageWithTemplatePainter({
    required this.templateImage,
    this.capturedImage,
    this.shapes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Draw captured image as background if available
    if (capturedImage != null) {
      // Calculate proper scaling to maintain aspect ratio
      final imageAspectRatio = capturedImage!.width / capturedImage!.height;
      final canvasAspectRatio = size.width / size.height;

      double scaleX, scaleY;
      double offsetX = 0, offsetY = 0;

      if (imageAspectRatio > canvasAspectRatio) {
        // Image is wider than canvas
        scaleX = scaleY = size.width / capturedImage!.width;
        offsetY = (size.height - (capturedImage!.height * scaleY)) / 2;
      } else {
        // Image is taller than canvas
        scaleX = scaleY = size.height / capturedImage!.height;
        offsetX = (size.width - (capturedImage!.width * scaleX)) / 2;
      }

      // Apply horizontal flip to correct the mirrored front camera image
      canvas.save();
      canvas.translate(offsetX + (capturedImage!.width * scaleX), offsetY);
      canvas.scale(-1.0, 1.0);

      final destRect = Rect.fromLTWH(
        0,
        0,
        capturedImage!.width * scaleX,
        capturedImage!.height * scaleY,
      );
      final srcRect = Rect.fromLTWH(
        0,
        0,
        capturedImage!.width.toDouble(),
        capturedImage!.height.toDouble(),
      );

      canvas.drawImageRect(capturedImage!, srcRect, destRect, paint);
      canvas.restore();
    }

    // Draw template image on top - template should have transparent areas where photo shows through
    final templateRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      templateImage,
      Rect.fromLTWH(
        0,
        0,
        templateImage.width.toDouble(),
        templateImage.height.toDouble(),
      ),
      templateRect,
      Paint(), // Use default paint without color overlay to preserve template's original transparency
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

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

class CameraTemplateReversePage extends StatefulWidget {
  final String? templateName;
  final String? originalImagePath;
  final List<Map<String, dynamic>>? shapes;
  final String? capturedImagePath; // Add parameter for captured photo

  const CameraTemplateReversePage({
    super.key,
    this.templateName,
    this.originalImagePath,
    this.shapes,
    this.capturedImagePath, // Add captured image path parameter
  });

  @override
  State<CameraTemplateReversePage> createState() =>
      _CameraTemplateReversePageState();
}

class _CameraTemplateReversePageState extends State<CameraTemplateReversePage>
    with TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCountingDown = false;

  // Template data
  String? _originalImagePath;
  ui.Image? _originalImage;
  bool _isLoadingTemplate = true;

  // Captured image data
  ui.Image? _capturedImage;
  bool _isLoadingCapturedImage = false;

  // Counter and capture data
  int _photoCounter = 0;
  int _printQuantity = 1; // Add print quantity counter
  String? _lastCapturedImagePath;
  final BluetoothPrinterService _printerService = BluetoothPrinterService();

  // Animation controllers for floating effect
  late AnimationController _animationController;
  late Animation<double> _floatingAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller for floating effect
    _animationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _floatingAnimation = Tween<double>(begin: -10.0, end: 10.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _initializeTemplate();
    _initializeCapturedImage();
    _initializeCamera();
  }

  Future<void> _initializeCapturedImage() async {
    if (widget.capturedImagePath == null) return;

    setState(() {
      _isLoadingCapturedImage = true;
    });

    try {
      final file = File(widget.capturedImagePath!);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();

        setState(() {
          _capturedImage = frame.image;
          _lastCapturedImagePath = widget.capturedImagePath;
          _photoCounter = 1; // Set counter to 1 since we have a captured photo
        });
      }
    } catch (e) {
      debugPrint('Error loading captured image: $e');
    } finally {
      setState(() {
        _isLoadingCapturedImage = false;
      });
    }
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
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
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
          });

          // Debug info
          debugPrint(
            'Camera initialized: ${selectedCamera.lensDirection} - ${selectedCamera.name}',
          );
          debugPrint('Satu kamera akan digunakan untuk kedua kolom');

          // Only start countdown if no captured image exists
          if (_capturedImage == null) {
            _startCountdown();
          }
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _startCountdown() async {
    if (_isCountingDown) return;

    setState(() {
      _isCountingDown = true;
    });

    // Wait for 3 seconds countdown
    for (int i = 3; i > 0; i--) {
      if (!mounted) return;
      await Future.delayed(const Duration(seconds: 1));
    }

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

      // Simply copy the image without any transformation first
      await File(image.path).copy(imagePath);

      // Load the captured image for display
      final bytes = await File(imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      if (mounted) {
        setState(() {
          _isCountingDown = false;
          _photoCounter++;
          _lastCapturedImagePath = imagePath;
          _capturedImage = frame.image; // Set captured image to display
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Foto ke-$_photoCounter berhasil diambil!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error capturing photo: $e');
      if (mounted) {
        setState(() {
          _isCountingDown = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal mengambil foto. Silakan coba lagi.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _printPhoto() async {
    if (_lastCapturedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tidak ada foto untuk dicetak. Ambil foto terlebih dahulu.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Ensure Bluetooth permissions are granted
      final hasPermission = await _printerService.requestPermissions();
      if (!hasPermission) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Izin Bluetooth diperlukan'),
            content: const Text(
              'Izin "Perangkat terdekat" (Nearby devices) tidak aktif.\n\n'
              'Aktifkan izin Bluetooth dan Nearby devices di Pengaturan aplikasi untuk melanjutkan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await openAppSettings();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );
        return;
      }

      // Ensure Bluetooth is enabled
      final isEnabled = await _printerService.isBluetoothEnabled();
      if (!isEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nyalakan Bluetooth terlebih dahulu untuk mencetak.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Handle printer connection
      PrinterBluetoothInfo? selectedDevice;
      final alreadyConnected = await _printerService.isConnected;

      if (alreadyConnected) {
        selectedDevice = _printerService.connectedDevice;
      } else if (_printerService.connectedDevice != null) {
        final reconnected = await _printerService.connectToPrinter(
          _printerService.connectedDevice!,
        );
        if (reconnected) {
          selectedDevice = _printerService.connectedDevice;
        }
      }

      // Show printer selection dialog if not connected
      if (!mounted) return;
      selectedDevice ??= await showDialog<PrinterBluetoothInfo>(
        context: context,
        builder: (context) => BluetoothPrinterDialog(
          onDeviceSelected: (device) {
            Navigator.of(context).pop(device);
          },
        ),
      );

      if (!mounted) return;

      if (selectedDevice != null) {
        // Navigate to PrintSuccessPage with all necessary data
        // PrintSuccessPage will handle the printing process
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => PrintSuccessPage(
              capturedImagePath: _lastCapturedImagePath,
              originalImage: _originalImage,
              capturedImage: _capturedImage,
              shapes: widget.shapes,
              printQuantity: _printQuantity,
            ),
          ),
          (route) => false, // Remove all previous routes
        );
      }
    } catch (e) {
      debugPrint('Error in _printPhoto: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terjadi kesalahan saat mencetak foto.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  void _retakePhoto() {
    // Return to the existing DualCameraPage instance with retake signal
    Navigator.of(context).pop('retake');
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller?.dispose();
    super.dispose();
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
            child: Column(
              children: [
                // Top Navigation Bar
                _buildTopNavigation(),

                // Main Content
                Expanded(
                  child: Row(
                    children: [
                      // // Left side - Template Display
                      Expanded(flex: 1, child: _buildTemplateSection()),

                      // Right side - Controls
                      Expanded(flex: 1, child: _buildControlsSection()),
                    ],
                  ),
                ),
              ],
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

  Widget _buildTopNavigation() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.transparent,
        // boxShadow: [
        //   BoxShadow(
        //     color: Colors.t,
        //     blurRadius: 10,
        //     offset: const Offset(0, 2),
        //   ),
        // ],
      ),
      child: Row(
        children: [
          // Logo
          Row(children: [Image.asset('assets/images/logo.png', width: 100)]),

          const Spacer(),

          // Navigation Menu
          // Row(
          //   children: [
          //     GestureDetector(
          //       onTap: () {
          //         Navigator.push(
          //           context,
          //           MaterialPageRoute(
          //             builder: (context) => const LandingPage(),
          //           ),
          //         );
          //       },
          //       child: _buildNavItem('Beranda', false),
          //     ),
          //     const SizedBox(width: 30),
          //     GestureDetector(
          //       onTap: () {
          //         Navigator.push(
          //           context,
          //           MaterialPageRoute(
          //             builder: (context) => const DualCameraPage(),
          //           ),
          //         );
          //       },
          //       child: _buildNavItem('Dual Camera', false),
          //     ),
          //     const SizedBox(width: 30),
          //     _buildNavItem('Fitur', false),
          //     const SizedBox(width: 30),
          //     _buildNavItem('Blog', false),
          //     const SizedBox(width: 40),
          //     Container(
          //       padding: const EdgeInsets.symmetric(
          //         horizontal: 20,
          //         vertical: 10,
          //       ),
          //       decoration: BoxDecoration(
          //         color: const Color(0xFFDC143C), // Red
          //         borderRadius: BorderRadius.circular(25),
          //         boxShadow: [
          //           BoxShadow(
          //             color: const Color(0xFFDC143C).withValues(alpha: 0.3),
          //             blurRadius: 8,
          //             offset: const Offset(0, 4),
          //           ),
          //         ],
          //       ),
          //       child: const Text(
          //         'Mulai',
          //         style: TextStyle(
          //           color: Colors.white,
          //           fontWeight: FontWeight.w600,
          //         ),
          //       ),
          //     ),
          //   ],
          // ),
      
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildTemplateSection() {
    return AnimatedBuilder(
      animation: _floatingAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatingAnimation.value),
          child: Container(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Container(
                width: 600, // Diperbesar dari 400 ke 500
                height: 550, // Diperbesar dari 300 ke 400
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _buildTemplateDisplay(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlsSection() {
    return Container(
      margin: EdgeInsets.only(right: 70),
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),

            // Main Controls with floating animation
            AnimatedBuilder(
              animation: _floatingAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -_floatingAnimation.value * 0.5 - 54),
                  child: _buildControlsPanel(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Print Quantity Counter
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                Text(
                  'Jumlah Print',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Minus Button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: IconButton(
                        onPressed:
                            _printQuantity > 1
                                ? () {
                                  setState(() {
                                    _printQuantity--;
                                  });
                                }
                                : null,
                        icon: const Icon(Icons.remove),
                        color: Colors.grey[600],
                        iconSize: 20,
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    ),

                    const SizedBox(width: 15),

                    // Quantity Display
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC143C),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFDC143C,
                            ).withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _printQuantity.toString(),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 15),

                    // Plus Button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: IconButton(
                        onPressed:
                            _printQuantity < 10
                                ? () {
                                  setState(() {
                                    _printQuantity++;
                                  });
                                }
                                : null,
                        icon: const Icon(Icons.add),
                        color: Colors.grey[600],
                        iconSize: 20,
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 15),

          // Action Buttons
          Column(
            children: [
              // Print Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _lastCapturedImagePath != null ? _printPhoto : null,
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.print,
                      color: Color(0xFFDC143C),
                      size: 18,
                    ),
                  ),
                  label: Text('Print $_printQuantity Foto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC143C),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    disabledForegroundColor: Colors.grey[600],
                    elevation: 6,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    shadowColor: const Color(0xFFDC143C).withValues(alpha: 0.3),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Retake Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: !_isCountingDown ? _retakePhoto : null,
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  label: const Text('Ambil Ulang'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.grey[700],
                    disabledBackgroundColor: Colors.grey[300],
                    disabledForegroundColor: Colors.grey[600],
                    elevation: 3,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateDisplay() {
    if (_isLoadingTemplate || _isLoadingCapturedImage) {
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

    // Template with captured image or live camera feed
    return Column(
      children: [
        // Template preview dengan ukuran yang proporsional
        Expanded(
          child: AspectRatio(
            aspectRatio: 4 / 5, // Rasio 4:5 untuk template yang lebih besar
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child:
                    _originalImage != null
                        ? (_capturedImage != null
                            ? // Show captured image with template overlay
                            CustomPaint(
                              painter: CapturedImageWithTemplatePainter(
                                templateImage: _originalImage!,
                                capturedImage: _capturedImage!,
                                shapes: widget.shapes,
                              ),
                            )
                            : // Show live camera feed with template overlay if no captured image
                            (_controller != null && _isInitialized
                                ? Stack(
                                  children: [
                                    // Live camera feed sebagai background with horizontal flip
                                    Positioned.fill(
                                      child: Center(
                                        child: AspectRatio(
                                          aspectRatio:
                                              _controller!.value.aspectRatio,
                                          child: Transform(
                                            alignment: Alignment.center,
                                            transform: Matrix4.diagonal3Values(
                                              -1.0,
                                              1.0,
                                              1.0,
                                            ), // Horizontal flip
                                            child: CameraPreview(_controller!),
                                          ),
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
                                  child: const Center(
                                    child: Text(
                                      'Preview tidak tersedia',
                                      style: TextStyle(
                                        color: Color(0xFF8B7355),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                )))
                        : Container(
                          color: const Color(0xFFF5F5F5),
                          child: const Center(
                            child: Text(
                              'Template tidak tersedia',
                              style: TextStyle(
                                color: Color(0xFF8B7355),
                                fontSize: 14,
                              ),
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
