import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'camera_template_reverse_page.dart';
import 'dart:convert';
import 'manual_segmentation_page.dart';

class DualCameraPage extends StatefulWidget {
  const DualCameraPage({super.key});

  @override
  State<DualCameraPage> createState() => _DualCameraPageState();
}

class _DualCameraPageState extends State<DualCameraPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animationController;
  late Animation<double> _floatingAnimation;
  CameraController? _cameraController1;
  CameraController? _cameraController2;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized2 = false;
  
  // Template overlay state
  String _templateName = 'default';
  Template? _templateData;
  List<SegShape> _templateShapes = [];
  bool _isTemplateLoaded = false;
  
  // Countdown variables
  Timer? _countdownTimer;
  int _countdownSeconds = 5;
  bool _isCountingDown = false;
  bool _showCountdown = false;
  
  // Camera state preservation
  bool _shouldPreserveCameras = false;
  bool _isNavigatingAway = false;
  bool _isDisposing = false; // Add flag to prevent concurrent disposal

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _animationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    
    _floatingAnimation = Tween<double>(
      begin: -10.0,
      end: 10.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _initializeCameras();
    _loadTemplateOverlay();
  }

  Future<void> _initializeCameras() async {
    try {
      debugPrint('DualCameraPage: Starting camera initialization');
      _cameras = await availableCameras();
      debugPrint('DualCameraPage: Found ${_cameras!.length} cameras');
      
      if (_cameras!.isNotEmpty) {
        // Find all front cameras
        List<CameraDescription> frontCameras = _cameras!
            .where((camera) => camera.lensDirection == CameraLensDirection.front)
            .toList();
        
        debugPrint('DualCameraPage: Found ${frontCameras.length} front cameras');
        
        // If we have at least one front camera, use it for both controllers
        // If we have multiple front cameras, use different ones
        if (frontCameras.isNotEmpty) {
          CameraDescription frontCamera1 = frontCameras.first;
          CameraDescription frontCamera2 = frontCameras.length > 1 
              ? frontCameras[1] 
              : frontCameras.first;
          
          debugPrint('DualCameraPage: Creating camera controllers');
          
          // Dispose existing controllers if they exist
          await _disposeControllers();
          
          // Initialize first camera with error handling
          try {
            _cameraController1 = CameraController(
              frontCamera1,
              ResolutionPreset.medium,
              enableAudio: false,
            );
            
            debugPrint('DualCameraPage: Initializing camera controller 1');
            await _cameraController1!.initialize();
            debugPrint('DualCameraPage: Camera controller 1 initialized successfully');
          } catch (e) {
            debugPrint('DualCameraPage: Error initializing camera 1: $e');
            _cameraController1?.dispose();
            _cameraController1 = null;
          }
          
          // Initialize second camera with error handling
          try {
            _cameraController2 = CameraController(
              frontCamera2,
              ResolutionPreset.medium,
              enableAudio: false,
            );
            
            debugPrint('DualCameraPage: Initializing camera controller 2');
            await _cameraController2!.initialize();
            debugPrint('DualCameraPage: Camera controller 2 initialized successfully');
          } catch (e) {
            debugPrint('DualCameraPage: Error initializing camera 2: $e');
            _cameraController2?.dispose();
            _cameraController2 = null;
          }
          
          // Check if at least camera 2 is initialized (main camera)
          if (_cameraController2 != null && _cameraController2!.value.isInitialized) {
            if (mounted) {
               debugPrint('DualCameraPage: Setting camera state to initialized');
               setState(() {
                 _isCameraInitialized2 = true;
               });
               
               debugPrint('DualCameraPage: Camera state updated - _isCameraInitialized2: $_isCameraInitialized2');
               debugPrint('DualCameraPage: Current state - _isCountingDown: $_isCountingDown, _isNavigatingAway: $_isNavigatingAway');
               
               // Auto-start countdown after a short delay to let UI stabilize
               Future.delayed(const Duration(milliseconds: 1000), () {
                 if (mounted && !_isCountingDown && !_isNavigatingAway) {
                   debugPrint('DualCameraPage: Conditions met, starting countdown timer');
                   _startCountdown();
                 } else {
                   debugPrint('DualCameraPage: Conditions not met for countdown - mounted: $mounted, _isCountingDown: $_isCountingDown, _isNavigatingAway: $_isNavigatingAway');
                 }
               });
             }
          } else {
            debugPrint('DualCameraPage: Failed to initialize main camera (camera 2)');
            // Retry after delay
            if (mounted) {
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) {
                  _initializeCameras();
                }
              });
            }
          }
        } else {
          debugPrint('DualCameraPage: No front cameras found');
          // Show error message to user
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tidak ada kamera depan yang tersedia'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        debugPrint('DualCameraPage: No cameras available');
        // Show error message to user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tidak ada kamera yang tersedia'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('DualCameraPage: Error initializing cameras: $e');
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error menginisialisasi kamera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      // Retry initialization after a delay
      if (mounted) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _initializeCameras();
          }
        });
      }
    }
  }

  Future<void> _loadTemplateOverlay() async {
    try {
      final tpl = await ShapeDatabase.instance.getTemplate(_templateName);
      final shapes = await ShapeDatabase.instance.getShapes(templateName: _templateName);
      if (mounted) {
        setState(() {
          _templateData = tpl;
          _templateShapes = shapes;
          _isTemplateLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('DualCameraPage: Error loading template overlay: $e');
      if (mounted) {
        setState(() {
          _isTemplateLoaded = false;
        });
      }
    }
  }

  Future<void> _disposeControllers() async {
    if (_isDisposing) {
      debugPrint('DualCameraPage: Already disposing controllers, skipping');
      return;
    }
    
    _isDisposing = true;
    debugPrint('DualCameraPage: Starting controller disposal');
    
    // Cancel any ongoing countdown to prevent interference
    _countdownTimer?.cancel();
    _countdownTimer = null;
    
    // Dispose camera 1
    if (_cameraController1 != null) {
      try {
        final controller1 = _cameraController1;
        _cameraController1 = null; // Set to null immediately to prevent race condition
        
        if (controller1 != null && controller1.value.isInitialized) {
          debugPrint('DualCameraPage: Disposing camera controller 1');
          await controller1.dispose();
          debugPrint('DualCameraPage: Camera controller 1 disposed successfully');
        }
      } catch (e) {
        debugPrint('DualCameraPage: Error disposing camera 1: $e');
      }
    }
    
    // Dispose camera 2
    if (_cameraController2 != null) {
      try {
        final controller2 = _cameraController2;
        _cameraController2 = null; // Set to null immediately to prevent race condition
        
        if (controller2 != null && controller2.value.isInitialized) {
          debugPrint('DualCameraPage: Disposing camera controller 2');
          await controller2.dispose();
          debugPrint('DualCameraPage: Camera controller 2 disposed successfully');
        }
      } catch (e) {
        debugPrint('DualCameraPage: Error disposing camera 2: $e');
      }
    }
    
    // Update UI state
    if (mounted) {
      setState(() {
        _isCameraInitialized2 = false;
        _isCountingDown = false;
        _showCountdown = false;
      });
    }
    
    _isDisposing = false;
    debugPrint('DualCameraPage: Controller disposal completed');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('DualCameraPage: App lifecycle state changed to: $state');
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App is paused or inactive, pause cameras but don't dispose if preserving
      if (!_shouldPreserveCameras && !_isDisposing) {
        debugPrint('DualCameraPage: Pausing cameras due to lifecycle change');
        _pauseCameras();
      }
    } else if (state == AppLifecycleState.resumed) {
      // App is resumed, check and reinitialize cameras if needed
      debugPrint('DualCameraPage: App resumed, checking camera state');
      if (!_isDisposing) {
        _checkAndReinitializeCameras();
        // Refresh template overlay in case it was updated elsewhere
        _loadTemplateOverlay();
      }
    } else if (state == AppLifecycleState.detached) {
      // App is being terminated, force dispose cameras
      debugPrint('DualCameraPage: App detached, force disposing cameras');
      _forceDisposeControllers();
    }
  }

  void _pauseCameras() {
    // Cancel countdown if running
    _countdownTimer?.cancel();
    _countdownTimer = null;
    
    // Don't dispose, just mark as not initialized to trigger reinit when needed
    if (mounted) {
      setState(() {
        _isCameraInitialized2 = false;
        _isCountingDown = false;
        _showCountdown = false;
      });
    }
  }

  void _checkAndReinitializeCameras() {
    if (_isDisposing) {
      debugPrint('DualCameraPage: Skipping camera check, disposal in progress');
      return;
    }
    
    // Check if cameras need reinitialization
    bool needsReinitialization = false;
    
    if (_cameraController1 == null || _cameraController2 == null) {
      debugPrint('DualCameraPage: Camera controllers are null, need reinitialization');
      needsReinitialization = true;
    } else {
      try {
        if (!_cameraController1!.value.isInitialized || !_cameraController2!.value.isInitialized) {
          debugPrint('DualCameraPage: Camera controllers not initialized, need reinitialization');
          needsReinitialization = true;
        }
      } catch (e) {
        debugPrint('DualCameraPage: Error checking camera state: $e');
        needsReinitialization = true;
      }
    }
    
    if (needsReinitialization) {
      debugPrint('DualCameraPage: Reinitializing cameras');
      _initializeCameras();
    } else if (!_isCameraInitialized2) {
      // Cameras exist but state is not updated
      setState(() {
        _isCameraInitialized2 = true;
      });
      if (!_isCountingDown && !_isNavigatingAway) {
        // Add delay before starting countdown to ensure UI is stable
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted && !_isCountingDown && !_isNavigatingAway && _isCameraInitialized2) {
            _startCountdown();
          }
        });
      }
    }
  }

  // Force dispose for app termination
  void _forceDisposeControllers() {
    debugPrint('DualCameraPage: Force disposing controllers');
    
    // Cancel any timers
    _countdownTimer?.cancel();
    _countdownTimer = null;
    
    // Force dispose without async/await to prevent hanging
    try {
      _cameraController1?.dispose();
    } catch (e) {
      debugPrint('DualCameraPage: Error force disposing camera 1: $e');
    }
    
    try {
      _cameraController2?.dispose();
    } catch (e) {
      debugPrint('DualCameraPage: Error force disposing camera 2: $e');
    }
    
    _cameraController1 = null;
    _cameraController2 = null;
  }

  Future<void> _captureAndNavigate() async {
    if (_cameraController2 == null || !_cameraController2!.value.isInitialized) {
      return;
    }

    try {
      // Preserve cameras before navigation
      _preserveCamerasForNavigation();
      
      // Capture photo from camera 2
      final image = await _cameraController2!.takePicture();
      final directory = await getApplicationDocumentsDirectory();
      final imagePath = '${directory.path}/dual_camera_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Copy the captured image to permanent location
      await File(image.path).copy(imagePath);

      setState(() {
        _isCountingDown = false;
        _showCountdown = false;
      });

      // Navigate to CameraTemplateReversePage with captured image
       if (mounted) {
         Navigator.push(
           context,
           MaterialPageRoute(
             builder: (context) => CameraTemplateReversePage(
               capturedImagePath: imagePath,
             ),
           ),
         ).then((result) {
           // Handle return from navigation
           if (mounted) {
             if (result == 'retake') {
               // User pressed retake, handle retake functionality
               debugPrint('DualCameraPage: Retake requested');
               _handleRetake();
             } else {
               // Normal return, resume camera operations
               _resumeCameraOperations();
             }
           }
         });
       }
    } catch (e) {
       debugPrint('Error capturing photo: $e');
       setState(() {
         _isCountingDown = false;
         _showCountdown = false;
       });
       // Reset preservation state on error
       _shouldPreserveCameras = false;
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
            child: Column(
              children: [
                // Top Navigation Bar
                _buildTopNavigation(),
                
                // Main Content
                Expanded(
                  child: Row(
                    children: [
                      // Left side - Dual cameras
                      Expanded(
                        flex: 1,
                        child: _buildDualCameraSection(),
                      ),
                      
                      // Right side - Call to action
                      Expanded(
                        flex: 1,
                        child: _buildCallToActionSection(),
                      ),
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
          top: -size.height * 0.2,  // Setengah ke atas pinggir
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
        
        // Blur effect (dibatasi agar tidak bocor ke tepi layar web)
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60.0, sigmaY: 60.0),
            child: Container(
              color: Colors.transparent,
            ),
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
        //     color: Colors.grey.withValues(alpha: 0.1),
        //     blurRadius: 10,
        //     offset: const Offset(0, 2),
        //   ),
        // ],
      ),
      child: Row(
        children: [
          // Logo
          Row(
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 100,
              ),
            ],
          ),
          
          const Spacer(),
          
          // Navigation Menu
          // Row(
          //   children: [
          //     _buildNavItem('Beranda', false),
          //     const SizedBox(width: 30),
          //     _buildNavItem('Dual Camera', true),
          //     const SizedBox(width: 30),
          //     _buildNavItem('Fitur', false),
          //     const SizedBox(width: 30),
          //     _buildNavItem('Blog', false),
          //     const SizedBox(width: 40),
          //     Container(
          //       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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



  // Method to handle retake functionality
  Future<void> _handleRetake() async {
    debugPrint('DualCameraPage: Handling retake request');
    
    // Reset all states including navigation flag
    setState(() {
      _isCountingDown = false;
      _showCountdown = false;
      _countdownSeconds = 5;
      _isNavigatingAway = false; // Reset navigation flag
      _shouldPreserveCameras = false; // Reset preservation flag
    });
    
    debugPrint('DualCameraPage: Reset navigation flags - _isNavigatingAway: $_isNavigatingAway, _shouldPreserveCameras: $_shouldPreserveCameras');
    
    // Cancel any ongoing countdown
    _countdownTimer?.cancel();
    _countdownTimer = null;
    
    // Force reinitialize cameras to ensure they work properly
    await _forceReinitializeCameras();
    
    // Start countdown after a short delay to ensure cameras are ready
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && !_isCountingDown && !_isNavigatingAway && _isCameraInitialized2) {
        debugPrint('DualCameraPage: Starting countdown after retake');
        _startCountdown();
      } else {
        debugPrint('DualCameraPage: Cannot start countdown after retake - mounted: $mounted, _isCountingDown: $_isCountingDown, _isNavigatingAway: $_isNavigatingAway, _isCameraInitialized2: $_isCameraInitialized2');
      }
    });
  }

  // Method to force reinitialize cameras (for retake scenarios)
  Future<void> _forceReinitializeCameras() async {
    debugPrint('DualCameraPage: Force reinitializing cameras for retake');
    
    // First dispose existing controllers
    await _disposeControllers();
    
    // Wait a bit to ensure cleanup is complete
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Then reinitialize
    await _initializeCameras();
  }

  @override
  void dispose() {
    debugPrint('DualCameraPage: Widget disposing');
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _countdownTimer?.cancel();
    
    // Always dispose cameras when widget is disposed, but don't wait
    _forceDisposeControllers();
    super.dispose();
  }

  void _startCountdown() {
    debugPrint('DualCameraPage: _startCountdown called');
    debugPrint('DualCameraPage: _isCountingDown = $_isCountingDown');
    debugPrint('DualCameraPage: _showCountdown = $_showCountdown');
    debugPrint('DualCameraPage: _isCameraInitialized2 = $_isCameraInitialized2');
    
    if (_isCountingDown) {
      debugPrint('DualCameraPage: Already counting down, returning');
      return;
    }
    
    debugPrint('DualCameraPage: Starting countdown timer');
    setState(() {
      _isCountingDown = true;
      _showCountdown = true;
      _countdownSeconds = 5;
    });

    debugPrint('DualCameraPage: State updated - _isCountingDown: $_isCountingDown, _showCountdown: $_showCountdown');

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      debugPrint('DualCameraPage: Countdown tick - $_countdownSeconds');
      setState(() {
        _countdownSeconds--;
      });

      if (_countdownSeconds <= 0) {
        debugPrint('DualCameraPage: Countdown finished, capturing photo');
        timer.cancel();
        _captureAndNavigate();
      }
    });
  }

  Widget _buildDualCameraSection() {
    return AnimatedBuilder(
      animation: _floatingAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatingAnimation.value),
          child: Container(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Second Camera
                  Container(
                    width: 380,
                    height: 420,
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
                      child: Stack(
                        children: [
                          _buildCameraPreviewCropped(
                            _cameraController2,
                            _isCameraInitialized2,
                            'Kamera Depan 1',
                          ),
                          
                          // Countdown overlay
                          if (_showCountdown)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _countdownSeconds.toString(),
                                        style: const TextStyle(
                                          fontSize: 80,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      const Text(
                                        'Bersiap untuk foto!',
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: Colors.white,
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  

  Widget _buildCameraPreviewCropped(CameraController? controller, bool isInitialized, String label) {
    if (isInitialized && controller != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final double containerWidth = constraints.maxWidth;
          final double containerHeight = constraints.maxHeight;
          final double containerAspectRatio = containerWidth / containerHeight;
          final double cameraAspectRatio = controller.value.aspectRatio;
          
          // Calculate scale to fill the container completely (crop if necessary)
          double scale;
          if (cameraAspectRatio > containerAspectRatio) {
            // Camera is wider than container, scale by height
            scale = containerHeight / (containerWidth / cameraAspectRatio);
          } else {
            // Camera is taller than container, scale by width
            scale = containerWidth / (containerHeight * cameraAspectRatio);
          }
          
          return ClipRect(
            child: Transform.scale(
              scale: scale,
              child: Center(
                child: AspectRatio(
                  aspectRatio: cameraAspectRatio,
                  child: CameraPreview(controller),
                ),
              ),
            ),
          );
        },
      );
    } else {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E90FF), // Blue
              Color(0xFF4169E1), // Royal Blue
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Menginisialisasi $label...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildCallToActionSection() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            
            // Template with Camera 2 Preview
            Container(
              width: 300,
              height: 450, // Rasio 4:5 untuk template
              margin: const EdgeInsets.only(bottom: 30),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 25,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    // Camera 2 positioned within template shape (behind template)
                    Builder(builder: (context) {
                      const double containerW = 300.0;
                      const double containerH = 450.0;
                      double left = (41.125 / 945.0) * containerW;
                      double top = (242.125 / 1417.0) * containerH;
                      double width = (890.75 / 945.0) * containerW;
                      double height = (950.25 / 1417.0) * containerH;

                      if (_templateShapes.isNotEmpty) {
                        final s = _templateShapes.first;
                        left = s.normalizedX * containerW;
                        top = s.normalizedY * containerH;
                        width = s.normalizedWidth * containerW;
                        height = s.normalizedHeight * containerH;
                      }

                      return Positioned(
                        left: left,
                        top: top,
                        width: width,
                        height: height,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _buildCameraPreviewCropped(
                            _cameraController2,
                            _isCameraInitialized2,
                            '',
                          ),
                        ),
                      );
                    }),
                    
                    // Template image in front (overlay)
                    Positioned.fill(
                      child: Builder(builder: (context) {
                        // Prefer template image from templates table; if absent, fallback to shape's imagePath
                        String path = _templateData?.imagePath ?? '';
                        if ((path.isEmpty || path == 'assets/images/template.png') && _templateShapes.isNotEmpty) {
                          path = _templateShapes.first.imagePath;
                        }
                        if (path.isEmpty) {
                          path = 'assets/images/template.png';
                        }
                        if (path.startsWith('assets/')) {
                          return Image.asset(path, fit: BoxFit.cover);
                        } else if (path.startsWith('data:image')) {
                          try {
                            final bytes = base64Decode(path.split(',').last);
                            return Image.memory(bytes, fit: BoxFit.cover);
                          } catch (e) {
                            debugPrint('DualCameraPage: Error decoding base64 template image: $e');
                            return Image.asset('assets/images/template.png', fit: BoxFit.cover);
                          }
                        } else if (File(path).existsSync()) {
                          return Image.file(File(path), fit: BoxFit.cover);
                        } else {
                          return Image.asset('assets/images/template.png', fit: BoxFit.cover);
                        }
                      }),
                    ),
                  ],
                ),
              ),
            ),
            
          ],
        ),
      ),
    );
  }

  // Method to preserve cameras during navigation
  void _preserveCamerasForNavigation() {
    debugPrint('DualCameraPage: Preserving cameras for navigation');
    _shouldPreserveCameras = true;
    _isNavigatingAway = true;
  }

  // Method to resume camera operations after returning from navigation
  void _resumeCameraOperations() {
    debugPrint('DualCameraPage: Resuming camera operations');
    _shouldPreserveCameras = false;
    _isNavigatingAway = false;
    
    // Always check and reinitialize cameras when returning
    _checkAndReinitializeCameras();
  }

}