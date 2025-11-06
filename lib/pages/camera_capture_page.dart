import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'photo_shape_display_page.dart';

class CameraCaptureData {
  final String templateName;
  final int shapeCount;
  final String originalImagePath;
  final List<Map<String, dynamic>> shapes;

  CameraCaptureData({
    required this.templateName,
    required this.shapeCount,
    required this.originalImagePath,
    required this.shapes,
  });
}

class CameraCapturePage extends StatefulWidget {
  final CameraCaptureData captureData;

  const CameraCapturePage({
    super.key,
    required this.captureData,
  });

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  int _currentPhotoIndex = 0;
  int _countdown = 0;
  Timer? _countdownTimer;
  final List<String> _capturedPhotos = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  void _startCountdown() {
    if (_isCapturing) return;
    
    setState(() {
      _isCapturing = true;
      _countdown = 3;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
      });

      if (_countdown <= 0) {
        timer.cancel();
        _capturePhoto();
      }
    });
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String captureDir = path.join(appDir.path, 'captures', widget.captureData.templateName);
      await Directory(captureDir).create(recursive: true);

      final String fileName = 'photo_${_currentPhotoIndex + 1}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String filePath = path.join(captureDir, fileName);

      final XFile photo = await _controller!.takePicture();
      await photo.saveTo(filePath);

      setState(() {
        _capturedPhotos.add(filePath);
        _currentPhotoIndex++;
        _isCapturing = false;
        _countdown = 0;
      });

      // Show capture success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Foto $_currentPhotoIndex dari ${widget.captureData.shapeCount} berhasil diambil!'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Check if all photos are captured
      if (_currentPhotoIndex >= widget.captureData.shapeCount) {
        await Future.delayed(const Duration(seconds: 1));
        _navigateToPhotoDisplay();
      }
    } catch (e) {
      setState(() {
        _isCapturing = false;
        _countdown = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error mengambil foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToPhotoDisplay() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => PhotoShapeDisplayPage(
          templateName: widget.captureData.templateName,
          originalImagePath: widget.captureData.originalImagePath,
          capturedPhotos: _capturedPhotos,
          shapes: widget.captureData.shapes,
        ),
      ),
    );
  }

  void _retakeCurrentPhoto() {
    if (_currentPhotoIndex > 0) {
      setState(() {
        _currentPhotoIndex--;
        _capturedPhotos.removeLast();
        _isCapturing = false;
        _countdown = 0;
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F5), // Soft cream background to match TemplateGalleryPage
      body: SafeArea(
        child: _isInitialized
            ? Column(
                children: [
                  // Header Section - removed back button
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                    child: Column(
                      children: [
                        // Removed back button row, only keep retake button if available
                        if (_currentPhotoIndex > 0)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.undo, color: Color(0xFF8B7355)),
                                onPressed: _retakeCurrentPhoto,
                                tooltip: 'Ulangi foto terakhir',
                              ),
                            ],
                          ),
                        const SizedBox(height: 20),
                        // Title with heart emoji - updated colors
                        RichText(
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: 'Warna ',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w300,
                                  color: Color(0xFF8B7355), // Updated to match TemplateGalleryPage
                                  fontFamily: 'serif',
                                ),
                              ),
                            
                              TextSpan(
                                text: 'Studio',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w300,
                                  color: Color(0xFF8B7355), // Updated to match TemplateGalleryPage
                                  fontFamily: 'serif',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Subtitle line - updated color
                        Container(
                          height: 1,
                          width: 120,
                          color: const Color(0xFFB8956A), // Updated to match TemplateGalleryPage
                        ),
                        const SizedBox(height: 20),
                        // Progress indicator - updated colors
                        Text(
                          'Foto $_currentPhotoIndex dari ${widget.captureData.shapeCount}',
                          style: const TextStyle(
                            color: Color(0xFF8B7355), // Updated to match TemplateGalleryPage
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _currentPhotoIndex / widget.captureData.shapeCount,
                          backgroundColor: Colors.white.withValues(alpha: 0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFB8956A)), // Updated to match TemplateGalleryPage
                          minHeight: 4,
                        ),
                      ],
                    ),
                  ),
                  
                  // Camera Preview Section
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                         borderRadius: BorderRadius.circular(20),
                         boxShadow: [
                           BoxShadow(
                             color: Colors.black.withValues(alpha: 0.1),
                             blurRadius: 10,
                             offset: const Offset(0, 5),
                           ),
                         ],
                       ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          children: [
                            // Camera Preview
                            Positioned.fill(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _controller!.value.previewSize!.height,
                                  height: _controller!.value.previewSize!.width,
                                  child: CameraPreview(_controller!),
                                ),
                              ),
                            ),
                            
                            // Countdown Overlay
                            if (_countdown > 0)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                           width: 120,
                                           height: 120,
                                           decoration: BoxDecoration(
                                             shape: BoxShape.circle,
                                             color: Colors.white.withValues(alpha: 0.9),
                                           ),
                                          child: Center(
                                            child: Text(
                                              '$_countdown',
                                              style: const TextStyle(
                                                fontSize: 60,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF8B7355), // Updated to match TemplateGalleryPage
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Container(
                                           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                           decoration: BoxDecoration(
                                             color: Colors.white.withValues(alpha: 0.9),
                                             borderRadius: BorderRadius.circular(20),
                                           ),
                                          child: Text(
                                            'Bersiap untuk foto ${_currentPhotoIndex + 1}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              color: Color(0xFF8B7355), // Updated to match TemplateGalleryPage
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Bottom Section
                  Container(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        // Instructions
                        if (!_isCapturing && _countdown == 0)
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                             decoration: BoxDecoration(
                               color: Colors.white.withValues(alpha: 0.8),
                               borderRadius: BorderRadius.circular(15),
                             ),
                            child: Text(
                              _currentPhotoIndex < widget.captureData.shapeCount
                                  ? 'Posisikan diri Anda dan tekan tombol untuk mengambil foto'
                                  : 'Semua foto telah diambil!',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF8B7355), // Updated to match TemplateGalleryPage
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        
                        const SizedBox(height: 20),
                        
                        // Take Photo Button - updated colors to match TemplateGalleryPage
                        GestureDetector(
                          onTap: _isCapturing ? null : _startCountdown,
                          child: Container(
                            width: double.infinity,
                            height: 60,
                            decoration: BoxDecoration(
                               gradient: _isCapturing 
                                   ? LinearGradient(
                                       colors: [Colors.grey.withValues(alpha: 0.6), Colors.grey.withValues(alpha: 0.4)],
                                     )
                                   : const LinearGradient(
                                       colors: [Color(0xFFB8956A), Color(0xFFE8D5C4)], // Updated to match TemplateGalleryPage
                                     ),
                               borderRadius: BorderRadius.circular(30),
                               boxShadow: _isCapturing ? [] : [
                                 BoxShadow(
                                   color: const Color(0xFFB8956A).withValues(alpha: 0.3), // Updated to match TemplateGalleryPage
                                   blurRadius: 10,
                                   offset: const Offset(0, 5),
                                 ),
                               ],
                             ),
                            child: Center(
                              child: Text(
                                _isCapturing ? 'MENGAMBIL FOTO...' : 'TAKE PHOTO',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Container(
                color: const Color(0xFFFDF8F5), // Updated to match TemplateGalleryPage
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: Color(0xFFB8956A), // Updated to match TemplateGalleryPage
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Mempersiapkan kamera...',
                        style: TextStyle(
                          color: Color(0xFF8B7355), // Updated to match TemplateGalleryPage
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}