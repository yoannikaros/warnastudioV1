import 'dart:io';
import 'dart:developer' as developer;
import '../pages/manual_segmentation_page.dart';

/// Helper class untuk operasi database yang lebih kompleks
class DatabaseHelper {
  /// Insert template default dengan data yang sudah ditentukan
  /// 
  /// Data default yang akan diinsert:
  /// - Template Name: conttt
  /// - Shape Type: rect
  /// - Position: (41.125, 242.125)
  /// - Size: 890.75 x 950.25
  /// - Image Size: 945.0 x 1417.0
  /// - Image Path: template.PNG
  static Future<bool> insertDefaultTemplate() async {
    try {
      developer.log('=== INSERTING DEFAULT TEMPLATE DATA ===', name: 'DatabaseHelper');
      
      // Data default berdasarkan informasi yang diberikan
      const String templateName = 'default';
      const String imagePath = 'assets/images/template.png';
      
      // Jika template default sudah ada, jangan menimpa data yang sudah diperbarui
      try {
        final existing = await ShapeDatabase.instance.getTemplate(templateName);
        if (existing != null) {
          developer.log('Default template already exists. Skipping insert to avoid overwriting updated image.', name: 'DatabaseHelper');
          return true;
        }
      } catch (_) {}

      developer.log('Using asset image path: $imagePath', name: 'DatabaseHelper');
      
      // Buat template object
      final template = Template(
        name: templateName,
        imagePath: imagePath,
        createdAt: DateTime.now(),
        shapeCount: 1, // Satu shape default
        description: 'Template default dengan shape rectangle',
      );
      
      developer.log('Creating template: ${template.name}', name: 'DatabaseHelper');
      
      // Insert template ke database
      await ShapeDatabase.instance.insertTemplate(template);
      
      // Hapus shape lama jika ada untuk template ini
      await ShapeDatabase.instance.deleteShapes(
        templateName: templateName,
        imagePath: imagePath,
      );
      
      // Buat shape default
      final defaultShape = SegShape(
        templateName: templateName,
        shapeType: 'rect',
        x: 41.125,
        y: 242.125,
        width: 890.75,
        height: 950.25,
        imageWidth: 945.0,
        imageHeight: 1417.0,
        imagePath: imagePath,
      );
      
      developer.log('Creating default shape:', name: 'DatabaseHelper');
      developer.log('  Template Name: ${defaultShape.templateName}', name: 'DatabaseHelper');
      developer.log('  Shape Type: ${defaultShape.shapeType}', name: 'DatabaseHelper');
      developer.log('  Position: (${defaultShape.x}, ${defaultShape.y})', name: 'DatabaseHelper');
      developer.log('  Size: ${defaultShape.width} x ${defaultShape.height}', name: 'DatabaseHelper');
      developer.log('  Image Size: ${defaultShape.imageWidth} x ${defaultShape.imageHeight}', name: 'DatabaseHelper');
      developer.log('  Normalized Position: (${defaultShape.normalizedX}, ${defaultShape.normalizedY})', name: 'DatabaseHelper');
      developer.log('  Normalized Size: ${defaultShape.normalizedWidth} x ${defaultShape.normalizedHeight}', name: 'DatabaseHelper');
      
      // Insert shape ke database
      await ShapeDatabase.instance.insertShape(defaultShape);
      
      developer.log('SUCCESS: Default template and shape inserted successfully', name: 'DatabaseHelper');
      return true;
      
    } catch (e) {
      developer.log('ERROR inserting default template: $e', name: 'DatabaseHelper');
      return false;
    }
  }
  
  /// Insert multiple default templates jika diperlukan di masa depan
  static Future<bool> insertMultipleDefaultTemplates(List<Map<String, dynamic>> templatesData) async {
    try {
      developer.log('=== INSERTING MULTIPLE DEFAULT TEMPLATES ===', name: 'DatabaseHelper');
      
      for (int i = 0; i < templatesData.length; i++) {
        final templateData = templatesData[i];
        developer.log('Processing template ${i + 1}/${templatesData.length}', name: 'DatabaseHelper');
        
        // Extract template info
        final templateName = templateData['template_name'] as String;
        final imagePath = templateData['image_path'] as String;
        final shapeType = templateData['shape_type'] as String;
        final x = (templateData['x'] as num).toDouble();
        final y = (templateData['y'] as num).toDouble();
        final width = (templateData['width'] as num).toDouble();
        final height = (templateData['height'] as num).toDouble();
        final imageWidth = (templateData['image_width'] as num).toDouble();
        final imageHeight = (templateData['image_height'] as num).toDouble();
        final radiusX = templateData['radiusX'] != null ? (templateData['radiusX'] as num).toDouble() : null;
        final radiusY = templateData['radiusY'] != null ? (templateData['radiusY'] as num).toDouble() : null;
        final rotation = templateData['rotation'] != null ? (templateData['rotation'] as num).toDouble() : null;
        
        // Cek apakah file gambar ada
        final imageFile = File(imagePath);
        if (!await imageFile.exists()) {
          developer.log('WARNING: Image file not found at $imagePath, skipping...', name: 'DatabaseHelper');
          continue;
        }
        
        // Buat template
        final template = Template(
          name: templateName,
          imagePath: imagePath,
          createdAt: DateTime.now(),
          shapeCount: 1,
          description: 'Template default - $templateName',
        );
        
        // Insert template
        await ShapeDatabase.instance.insertTemplate(template);
        
        // Hapus shape lama
        await ShapeDatabase.instance.deleteShapes(
          templateName: templateName,
          imagePath: imagePath,
        );
        
        // Buat shape
        final shape = SegShape(
          templateName: templateName,
          shapeType: shapeType,
          x: x,
          y: y,
          width: width,
          height: height,
          radiusX: radiusX,
          radiusY: radiusY,
          rotation: rotation,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          imagePath: imagePath,
        );
        
        // Insert shape
        await ShapeDatabase.instance.insertShape(shape);
        
        developer.log('Template "$templateName" inserted successfully', name: 'DatabaseHelper');
      }
      
      developer.log('SUCCESS: All default templates inserted', name: 'DatabaseHelper');
      return true;
      
    } catch (e) {
      developer.log('ERROR inserting multiple default templates: $e', name: 'DatabaseHelper');
      return false;
    }
  }
  
  /// Cek apakah template default sudah ada
  static Future<bool> isDefaultTemplateExists() async {
    try {
      final template = await ShapeDatabase.instance.getTemplate('default');
      return template != null;
    } catch (e) {
      developer.log('ERROR checking default template: $e', name: 'DatabaseHelper');
      return false;
    }
  }
  
  /// Initialize database dengan data default jika belum ada
  static Future<void> initializeWithDefaultData() async {
    try {
      developer.log('=== INITIALIZING DATABASE WITH DEFAULT DATA ===', name: 'DatabaseHelper');
      
      final exists = await isDefaultTemplateExists();
      if (!exists) {
        developer.log('Default template not found, inserting...', name: 'DatabaseHelper');
        await insertDefaultTemplate();
      } else {
        developer.log('Default template already exists, skipping...', name: 'DatabaseHelper');
      }
      
    } catch (e) {
      developer.log('ERROR initializing database: $e', name: 'DatabaseHelper');
    }
  }
}