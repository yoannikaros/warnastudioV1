import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:ui';
import 'dual_camera_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _floatingAnimation;
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    
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
    
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        // Use front camera if available, otherwise use first camera
        CameraDescription frontCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first,
        );
        
        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _cameraController?.dispose();
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
                      // Left side - Photo booth image
                      Expanded(
                        flex: 1,
                        child: _buildPhotoBoothSection(),
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
          filter: ImageFilter.blur(sigmaX: 60.0, sigmaY: 60.0),
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
               // height: 40,
              ),

            ],
          ),
          
          const Spacer(),
          
          // Navigation Menu
          // Row(
          //   children: [
          //     _buildNavItem('Beranda', true),
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

  Widget _buildPhotoBoothSection() {
    return AnimatedBuilder(
      animation: _floatingAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatingAnimation.value - 30),
          child: Container(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Container(
                width: 400,
                height: 300,
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
                  child: _isCameraInitialized && _cameraController != null
                      ? Stack(
                          children: [
                            // Camera Preview
                            Positioned.fill(
                              child: Transform.scale(
                                scale: 1.0,
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio: _cameraController!.value.aspectRatio,
                                    child: CameraPreview(_cameraController!),
                                  ),
                                ),
                              ),
                            ),
                            
                            // Overlay with camera info
                            Positioned(
                              bottom: 20,
                              left: 20,
                              right: 20,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Kamera Depan',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
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
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Menginisialisasi Kamera...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
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
        );
      },
    );
  }

  Widget _buildCallToActionSection() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            
            // Main CTA Button
            AnimatedBuilder(
              animation: _floatingAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -_floatingAnimation.value * 0.5 - 30),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        // Navigate to CameraTemplatePage
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DualCameraPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white, // Yellow
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 50,
                          vertical: 20,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white, // Red
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Text(
                            'Click To Start',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

}