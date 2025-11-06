import 'package:flutter/material.dart';
import 'dart:ui';


class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
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
}