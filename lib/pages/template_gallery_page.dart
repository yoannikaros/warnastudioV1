import 'dart:io';
import 'package:flutter/material.dart';
import 'manual_segmentation_page.dart';
import 'camera_capture_page.dart';

// Model untuk template data
class TemplateData {
  final String templateName;
  final String imagePath;
  final int shapeCount;
  final DateTime? lastModified;

  TemplateData({
    required this.templateName,
    required this.imagePath,
    required this.shapeCount,
    this.lastModified,
  });
}

class TemplateGalleryPage extends StatefulWidget {
  const TemplateGalleryPage({super.key});

  @override
  State<TemplateGalleryPage> createState() => _TemplateGalleryPageState();
}

class _TemplateGalleryPageState extends State<TemplateGalleryPage> {
  List<TemplateData> _templates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final db = await ShapeDatabase.instance.database;
      
      // Query untuk mendapatkan semua template dengan jumlah shapes
      final result = await db.rawQuery('''
        SELECT 
          template_name,
          image_path,
          COUNT(*) as shape_count
        FROM shapes 
        GROUP BY template_name, image_path
        ORDER BY template_name
      ''');

      final templates = <TemplateData>[];
      
      for (final row in result) {
        final templateName = row['template_name'] as String;
        final imagePath = row['image_path'] as String;
        final shapeCount = row['shape_count'] as int;
        
        // Cek apakah file gambar masih ada
        final file = File(imagePath);
        if (await file.exists()) {
          final stat = await file.stat();
          templates.add(TemplateData(
            templateName: templateName,
            imagePath: imagePath,
            shapeCount: shapeCount,
            lastModified: stat.modified,
          ));
        }
      }

      setState(() {
        _templates = templates;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading templates: $e')),
        );
      }
    }
  }

  Future<void> _openTemplate(TemplateData template) async {
    try {
      // Get shapes data for this template
      final shapes = await ShapeDatabase.instance.getShapes(
        templateName: template.templateName,
        imagePath: template.imagePath,
      );

      if (shapes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Template tidak memiliki shape yang valid'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Convert SegShape to Map for camera page
      final shapesData = shapes.map((shape) => {
        'template_name': shape.templateName,
        'shape_type': shape.shapeType,
        'x': shape.x,
        'y': shape.y,
        'width': shape.width,
        'height': shape.height,
        'radiusX': shape.radiusX,
        'radiusY': shape.radiusY,
        'rotation': shape.rotation,
        'image_width': shape.imageWidth,
        'image_height': shape.imageHeight,
        'image_path': shape.imagePath,
        'normalized_x': shape.normalizedX,
        'normalized_y': shape.normalizedY,
        'normalized_width': shape.normalizedWidth,
        'normalized_height': shape.normalizedHeight,
        'normalized_radiusX': shape.normalizedRadiusX,
        'normalized_radiusY': shape.normalizedRadiusY,
      }).toList();

      // Navigate to camera page
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CameraCapturePage(
              captureData: CameraCaptureData(
                templateName: template.templateName,
                shapeCount: template.shapeCount,
                originalImagePath: template.imagePath,
                shapes: shapesData,
              ),
            ),
          ),
        ).then((_) {
          // Refresh templates when returning
          _loadTemplates();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading template: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F5), // Soft cream background
      body: SafeArea(
        child: Column(
          children: [
            // Elegant header with wedding theme
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFDF8F5),
                    Color(0xFFF9F1EB),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Title with elegant wedding styling
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8D5C4).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.photo_library_rounded,
                          color: Color(0xFFB8956A),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Choose Photo',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w300,
                          color: Color(0xFF8B7355),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pilih template untuk foto Anda',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            
            // Content area
            Expanded(
              child: _isLoading
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
                            'Memuat template...',
                            style: TextStyle(
                              color: Color(0xFF8B7355),
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _templates.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(40),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 20,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8D5C4).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Icon(
                                        Icons.photo_library_outlined,
                                        size: 48,
                                        color: Color(0xFFB8956A),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    const Text(
                                      'Belum ada template',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w300,
                                        color: Color(0xFF8B7355),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Mulai buat template foto\npernikahan pertama Anda',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),
                              _buildCreateButton(),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadTemplates,
                          color: const Color(0xFFB8956A),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: MediaQuery.of(context).size.width > MediaQuery.of(context).size.height ? 4 : 2, // 4 columns in landscape, 2 in portrait
                                crossAxisSpacing: 20,
                                mainAxisSpacing: 20,
                                childAspectRatio: 0.8,
                              ),
                              itemCount: _templates.length,
                              itemBuilder: (context, index) {
                                final template = _templates[index];
                                return _buildTemplateCard(template);
                              },
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _templates.isNotEmpty ? _buildFloatingActionButton() : null,
    );
  }

  Widget _buildCreateButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB8956A), Color(0xFFE8D5C4)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8956A).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ManualSegmentationPage(),
            ),
          ).then((_) => _loadTemplates());
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Buat Template Baru',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB8956A), Color(0xFFE8D5C4)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8956A).withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ManualSegmentationPage(),
            ),
          ).then((_) => _loadTemplates());
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        tooltip: 'Buat Template Baru',
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildTemplateCard(TemplateData template) {
    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openTemplate(template),
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Template preview with elegant frame
              Expanded(
                flex: 3,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFE8D5C4).withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        // Background image
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFFFDF8F5),
                                Colors.grey[100]!,
                              ],
                            ),
                          ),
                          child: File(template.imagePath).existsSync()
                              ? Image.file(
                                  File(template.imagePath),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildErrorPlaceholder();
                                  },
                                )
                              : _buildErrorPlaceholder(),
                        ),
                        // Shape thumbnails overlay
                        FutureBuilder<List<SegShape>>(
                          future: ShapeDatabase.instance.getShapes(
                            templateName: template.templateName,
                            imagePath: template.imagePath,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                              return CustomPaint(
                                painter: ShapeThumbnailPainter(
                                  shapes: snapshot.data!,
                                ),
                                size: Size.infinite,
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        // Elegant overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.1),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Template info with wedding styling
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Template name
                      Text(
                        template.templateName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF8B7355),
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      
                      // Shape count with elegant styling
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8D5C4).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.crop_free,
                              size: 16,
                              color: Color(0xFFB8956A),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${template.shapeCount} foto',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFB8956A),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // // Action hint
                      // Container(
                      //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      //   decoration: BoxDecoration(
                      //     color: const Color(0xFFFDF8F5),
                      //     borderRadius: BorderRadius.circular(8),
                      //     border: Border.all(
                      //       color: const Color(0xFFE8D5C4).withValues(alpha: 0.5),
                      //     ),
                      //   ),
                      //   child: Row(
                      //     mainAxisSize: MainAxisSize.min,
                      //     children: [
                      //       Icon(
                      //         Icons.touch_app,
                      //         size: 14,
                      //         color: Colors.grey[600],
                      //       ),
                      //       const SizedBox(width: 4),
                      //       Text(
                      //         'Ketuk untuk mulai',
                      //         style: TextStyle(
                      //           fontSize: 11,
                      //           color: Colors.grey[600],
                      //           fontWeight: FontWeight.w400,
                      //         ),
                      //       ),
                      //     ],
                      //   ),
                      // ),
                    
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFDF8F5),
            Colors.grey[200]!,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8D5C4).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.broken_image_outlined,
                size: 24,
                color: Color(0xFFB8956A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Gambar tidak\nditemukan',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom painter untuk menampilkan thumbnail shapes
class ShapeThumbnailPainter extends CustomPainter {
  final List<SegShape> shapes;

  ShapeThumbnailPainter({required this.shapes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFFB8956A).withValues(alpha: 0.8);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFB8956A).withValues(alpha: 0.1);

    for (final shape in shapes) {
      final normalizedX = shape.normalizedX * size.width;
      final normalizedY = shape.normalizedY * size.height;
      final normalizedWidth = shape.normalizedWidth * size.width;
      final normalizedHeight = shape.normalizedHeight * size.height;

      switch (shape.shapeType) {
        case 'rect':
        case 'square':
          final rect = Rect.fromLTWH(
            normalizedX,
            normalizedY,
            normalizedWidth,
            normalizedHeight,
          );
          canvas.drawRect(rect, fillPaint);
          canvas.drawRect(rect, paint);
          break;
        case 'circle':
        case 'ellipse':
          final center = Offset(
            normalizedX + normalizedWidth / 2,
            normalizedY + normalizedHeight / 2,
          );
          if (shape.shapeType == 'circle') {
            final radius = normalizedWidth / 2;
            canvas.drawCircle(center, radius, fillPaint);
            canvas.drawCircle(center, radius, paint);
          } else {
            final rect = Rect.fromCenter(
              center: center,
              width: normalizedWidth,
              height: normalizedHeight,
            );
            canvas.drawOval(rect, fillPaint);
            canvas.drawOval(rect, paint);
          }
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}