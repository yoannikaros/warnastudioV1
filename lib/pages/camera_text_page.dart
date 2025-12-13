import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'camera_template_page.dart';

class CameraTextPage extends StatefulWidget {
  const CameraTextPage({super.key});

  @override
  State<CameraTextPage> createState() => _CameraTextPageState();
}

class _CameraTextPageState extends State<CameraTextPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isFrontCamera = true;
  bool _isLandscape = true; // State untuk orientasi (true = landscape, false = portrait)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOrientation();
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _setOrientation();
    }
  }

  void _setOrientation() {
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
    });
    _setOrientation();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Cari kamera depan terlebih dahulu
        CameraDescription? frontCamera;
        for (var camera in _cameras!) {
          if (camera.lensDirection == CameraLensDirection.front) {
            frontCamera = camera;
            break;
          }
        }
        
        // Jika tidak ada kamera depan, gunakan kamera pertama yang tersedia
        final selectedCamera = frontCamera ?? _cameras!.first;
        
        _controller = CameraController(
          selectedCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );

        await _controller!.initialize();
        
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _isFrontCamera = selectedCamera.lensDirection == CameraLensDirection.front;
          });
          
          // Pastikan orientasi sesuai state setelah setState
          _setOrientation();
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    // Reset orientasi ke semua orientasi ketika halaman ditutup
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
    // Pastikan orientasi sesuai dengan state
    _setOrientation();
    
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;
    
    // Responsive sizing berdasarkan orientasi
    final logoSize = _isLandscape ? 70.0 : 60.0;
    final containerMargin = _isLandscape ? 16.0 : 12.0;
    final containerPadding = _isLandscape ? 24.0 : 20.0;
    final buttonPadding = _isLandscape ? 28.0 : 24.0;
    final fontSize = _isLandscape ? 36.0 : 28.0;
    final borderRadius = 20.0;
    final buttonBorderRadius = 18.0;
    
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
              // Main content dengan layout responsif berdasarkan orientasi
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * (_isLandscape ? 0.04 : 0.06),
                  vertical: screenHeight * (_isLandscape ? 0.03 : 0.04),
                ),
                child: _isLandscape 
                   ? Row( // Layout landscape menggunakan Row
                       children: _buildLayoutChildren(containerMargin, borderRadius, containerPadding, isTablet, buttonPadding, buttonBorderRadius, fontSize, screenHeight, screenWidth),
                     )
                   : Column( // Layout portrait menggunakan Column
                       children: _buildLayoutChildren(containerMargin, borderRadius, containerPadding, isTablet, buttonPadding, buttonBorderRadius, fontSize, screenHeight, screenWidth),
                     ),
              ),
              
              // Simple Logo Header with responsive positioning
              Positioned(
                top: isTablet ? 40 : 30,
                left: isTablet ? 40 : 25,
                child: Image.asset(
                  'assets/images/logo.png',
                  height: logoSize,
                  width: logoSize,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Initializing Camera...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = MediaQuery.of(context).size.width > 600;
        final overlayTop = isTablet ? 16.0 : 10.0;
        final overlayLeft = isTablet ? 16.0 : 10.0;
        final iconSize = isTablet ? 20.0 : 16.0;
        final textSize = isTablet ? 14.0 : 12.0;
        final overlayPadding = isTablet ? 16.0 : 12.0;
        
        return Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview yang mengisi seluruh container
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize?.height ?? 1,
                  height: _controller!.value.previewSize?.width ?? 1,
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
            
            // Tombol orientasi - positioned di kanan atas
            Positioned(
              top: overlayTop,
              right: overlayLeft,
              child: GestureDetector(
                onTap: _toggleOrientation,
                child: Container(
                  padding: EdgeInsets.all(overlayPadding * 0.8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(isTablet ? 24 : 20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLandscape ? Icons.screen_rotation : Icons.stay_current_portrait,
                        color: Colors.white,
                        size: iconSize,
                      ),
                      SizedBox(width: isTablet ? 6 : 4),
                      Text(
                        _isLandscape ? 'Landscape' : 'Portrait',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: textSize * 0.9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Overlay dengan informasi kamera - responsive positioning
            Positioned(
              top: overlayTop,
              left: overlayLeft,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: overlayPadding,
                  vertical: overlayPadding * 0.5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(isTablet ? 24 : 20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isFrontCamera ? Icons.camera_front : Icons.camera_rear,
                      color: Colors.white,
                      size: iconSize,
                    ),
                    SizedBox(width: isTablet ? 8 : 6),
                    Text(
                      _isFrontCamera ? 'Front' : 'Back',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: textSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildLayoutChildren(double containerMargin, double borderRadius, double containerPadding, bool isTablet, double buttonPadding, double buttonBorderRadius, double fontSize, double screenHeight, double screenWidth) {
    return [
      // Bagian Kamera
      Expanded(
        flex: _isLandscape ? 1 : 4, // Setengah layar di landscape (1:1 ratio)
        child: Container(
          margin: EdgeInsets.all(containerMargin),
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: _buildCameraPreview(),
          ),
        ),
      ),
      
      // Bagian Tombol CLICK TO START
      Expanded(
        flex: _isLandscape ? 1 : 2, // Setengah layar di landscape (1:1 ratio)
        child: Container(
          padding: EdgeInsets.all(containerPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildClickToStartButton(isTablet, buttonPadding, buttonBorderRadius, fontSize),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildClickToStartButton(bool isTablet, double buttonPadding, double buttonBorderRadius, double fontSize) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CameraTemplatePage(),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: buttonPadding * 1.5,
          vertical: buttonPadding,
        ),
        constraints: BoxConstraints(
          maxWidth: 350, // Always use landscape maxWidth
          minHeight: 80, // Always use landscape minHeight
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(buttonBorderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 25, // Always use landscape blur radius
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Text(
          'CLICK TO START',
          textAlign: TextAlign.center,
          style: GoogleFonts.jersey10(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
            letterSpacing: isTablet ? 3 : 2,
          ),
        ),
      ),
    );
  }
}