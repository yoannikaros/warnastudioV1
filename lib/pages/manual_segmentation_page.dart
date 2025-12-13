import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:ui' as ui;
import '../helpers/database_helper.dart';

// Data model untuk template
class Template {
  final String name;
  final String imagePath;
  final DateTime createdAt;
  final int shapeCount;
  final String? description;

  Template({
    required this.name,
    required this.imagePath,
    required this.createdAt,
    required this.shapeCount,
    this.description,
  });

  Map<String, Object?> toMap() => {
        'name': name,
        'image_path': imagePath,
        'created_at': createdAt.millisecondsSinceEpoch,
        'shape_count': shapeCount,
        'description': description,
      };

  factory Template.fromMap(Map<String, Object?> map) {
    return Template(
      name: (map['name'] ?? '') as String,
      imagePath: (map['image_path'] ?? '') as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['created_at'] ?? 0) as int),
      shapeCount: (map['shape_count'] ?? 0) as int,
      description: map['description'] as String?,
    );
  }
}

// Data model untuk shape
class SegShape {
  SegShape({
    required this.templateName,
    required this.shapeType,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.radiusX,
    this.radiusY,
    this.rotation,
    required this.imageWidth,
    required this.imageHeight,
    required this.imagePath,
  }) {
    normalizedX = x / imageWidth;
    normalizedY = y / imageHeight;
    normalizedWidth = width / imageWidth;
    normalizedHeight = height / imageHeight;
    if (radiusX != null) normalizedRadiusX = radiusX! / imageWidth;
    if (radiusY != null) normalizedRadiusY = radiusY! / imageHeight;
  }

  final String templateName;
  final String shapeType; // 'rect', 'square', 'circle', 'ellipse'
  final double x;
  final double y;
  final double width;
  final double height;
  final double? radiusX;
  final double? radiusY;
  final double? rotation;
  final double imageWidth;
  final double imageHeight;
  final String imagePath;

  late final double normalizedX;
  late final double normalizedY;
  late final double normalizedWidth;
  late final double normalizedHeight;
  double? normalizedRadiusX;
  double? normalizedRadiusY;

  Map<String, Object?> toMap() => {
        'template_name': templateName,
        'shape_type': shapeType,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'radiusX': radiusX,
        'radiusY': radiusY,
        'rotation': rotation,
        'image_width': imageWidth,
        'image_height': imageHeight,
        'image_path': imagePath,
        'normalized_x': normalizedX,
        'normalized_y': normalizedY,
        'normalized_width': normalizedWidth,
        'normalized_height': normalizedHeight,
        'normalized_radiusX': normalizedRadiusX,
        'normalized_radiusY': normalizedRadiusY,
      };
  factory SegShape.fromMap(Map<String, Object?> map) {
    double toDouble(Object? v) => v is int ? v.toDouble() : (v as double);
    return SegShape(
      templateName: (map['template_name'] ?? 'default') as String,
      shapeType: (map['shape_type'] ?? 'rect') as String,
      x: toDouble(map['x']),
      y: toDouble(map['y']),
      width: toDouble(map['width']),
      height: toDouble(map['height']),
      radiusX: map['radiusX'] != null ? toDouble(map['radiusX']) : null,
      radiusY: map['radiusY'] != null ? toDouble(map['radiusY']) : null,
      rotation: map['rotation'] != null ? toDouble(map['rotation']) : null,
      imageWidth: toDouble(map['image_width']),
      imageHeight: toDouble(map['image_height']),
      imagePath: (map['image_path'] ?? '') as String,
    );
  }
}

// Custom painter untuk menggambar shape sesuai tipe
class SegShapePainter extends CustomPainter {
  final String shapeType;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  SegShapePainter({
    required this.shapeType,
    required this.fillColor,
    required this.strokeColor,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;

    switch (shapeType) {
      case 'rect':
      case 'square':
        final rect = Rect.fromLTWH(0, 0, size.width, size.height);
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, strokePaint);
        break;
      case 'circle':
        final r = math.min(size.width, size.height) / 2;
        final center = Offset(size.width / 2, size.height / 2);
        canvas.drawCircle(center, r, fillPaint);
        canvas.drawCircle(center, r, strokePaint);
        break;
      case 'ellipse':
        final rect = Rect.fromLTWH(0, 0, size.width, size.height);
        canvas.drawOval(rect, fillPaint);
        canvas.drawOval(rect, strokePaint);
        break;
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant SegShapePainter oldDelegate) {
    return shapeType != oldDelegate.shapeType ||
        fillColor != oldDelegate.fillColor ||
        strokeColor != oldDelegate.strokeColor ||
        strokeWidth != oldDelegate.strokeWidth;
  }
}

// Service database yang diperluas untuk template
class ShapeDatabase {
  ShapeDatabase._();
  static final ShapeDatabase instance = ShapeDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/seg_shapes.db';
    _db = await openDatabase(path);
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS shapes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        template_name TEXT,
        shape_type TEXT,
        x REAL,
        y REAL,
        width REAL,
        height REAL,
        radiusX REAL,
        radiusY REAL,
        rotation REAL,
        image_width REAL,
        image_height REAL,
        image_path TEXT,
        normalized_x REAL,
        normalized_y REAL,
        normalized_width REAL,
        normalized_height REAL,
        normalized_radiusX REAL,
        normalized_radiusY REAL
      );
    ''');
    
    // Create templates table
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE,
        image_path TEXT,
        created_at INTEGER,
        shape_count INTEGER,
        description TEXT
      );
    ''');
    return _db!;
  }

  Future<int> insertShape(SegShape shape) async {
    final db = await database;
    
    // Log data shape yang diterima oleh helper
    developer.log('=== INSERT SHAPE TO DATABASE ===', name: 'ShapeDatabase');
    developer.log('Received shape data:', name: 'ShapeDatabase');
    developer.log('  Template Name: ${shape.templateName}', name: 'ShapeDatabase');
    developer.log('  Shape Type: ${shape.shapeType}', name: 'ShapeDatabase');
    developer.log('  Position: (${shape.x}, ${shape.y})', name: 'ShapeDatabase');
    developer.log('  Size: ${shape.width} x ${shape.height}', name: 'ShapeDatabase');
    developer.log('  Image Path: ${shape.imagePath}', name: 'ShapeDatabase');
    developer.log('  Full Map Data: ${shape.toMap()}', name: 'ShapeDatabase');
    
    return db.insert('shapes', shape.toMap());
  }

  Future<List<SegShape>> getShapes({String? imagePath, String? templateName}) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (imagePath != null) {
      whereClauses.add('image_path = ?');
      whereArgs.add(imagePath);
    }
    if (templateName != null) {
      whereClauses.add('template_name = ?');
      whereArgs.add(templateName);
    }
    final where = whereClauses.isEmpty ? null : whereClauses.join(' AND ');
    final maps = await db.query('shapes', where: where, whereArgs: whereArgs);
    return maps.map((m) => SegShape.fromMap(m)).toList();
  }

  Future<int> deleteShapes({String? imagePath, String? templateName}) async {
    final db = await database;
    
    // Log data yang diterima untuk delete operation
    developer.log('=== DELETE SHAPES FROM DATABASE ===', name: 'ShapeDatabase');
    developer.log('Delete parameters:', name: 'ShapeDatabase');
    developer.log('  Image Path: ${imagePath ?? "null"}', name: 'ShapeDatabase');
    developer.log('  Template Name: ${templateName ?? "null"}', name: 'ShapeDatabase');
    
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (imagePath != null) {
      whereClauses.add('image_path = ?');
      whereArgs.add(imagePath);
    }
    if (templateName != null) {
      whereClauses.add('template_name = ?');
      whereArgs.add(templateName);
    }
    final where = whereClauses.isEmpty ? null : whereClauses.join(' AND ');
    
    developer.log('  WHERE clause: ${where ?? "null"}', name: 'ShapeDatabase');
    developer.log('  WHERE args: $whereArgs', name: 'ShapeDatabase');
    
    return db.delete('shapes', where: where, whereArgs: whereArgs);
  }

  Future<List<String>> getTemplateNames({String? imagePath}) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (imagePath != null) {
      whereClauses.add('image_path = ?');
      whereArgs.add(imagePath);
    }
    final where = whereClauses.isEmpty ? '' : 'WHERE ${whereClauses.join(' AND ')}';
    final res = await db.rawQuery('SELECT DISTINCT template_name FROM shapes $where', whereArgs);
    return res.map((m) => (m['template_name'] as String?) ?? 'default').toList();
  }

  Future<String?> getImagePathForTemplate(String templateName) async {
    final db = await database;
    final maps = await db.query(
      'shapes',
      columns: ['image_path'],
      where: 'template_name = ?',
      whereArgs: [templateName],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final ip = maps.first['image_path'] as String?;
    return ip;
  }

  // Template CRUD operations
  Future<int> insertTemplate(Template template) async {
    final db = await database;
    
    // Log data template yang diterima oleh helper
    developer.log('=== INSERT TEMPLATE TO DATABASE ===', name: 'ShapeDatabase');
    developer.log('Received template data:', name: 'ShapeDatabase');
    developer.log('  Name: ${template.name}', name: 'ShapeDatabase');
    developer.log('  Image Path: ${template.imagePath}', name: 'ShapeDatabase');
    developer.log('  Created At: ${template.createdAt}', name: 'ShapeDatabase');
    developer.log('  Shape Count: ${template.shapeCount}', name: 'ShapeDatabase');
    developer.log('  Description: ${template.description}', name: 'ShapeDatabase');
    developer.log('  Full Map Data: ${template.toMap()}', name: 'ShapeDatabase');
    
    return db.insert('templates', template.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Template>> getAllTemplates() async {
    final db = await database;
    final maps = await db.query('templates', orderBy: 'created_at DESC');
    return maps.map((m) => Template.fromMap(m)).toList();
  }

  Future<Template?> getTemplate(String name) async {
    final db = await database;
    final maps = await db.query('templates', where: 'name = ?', whereArgs: [name], limit: 1);
    if (maps.isEmpty) return null;
    return Template.fromMap(maps.first);
  }

  Future<int> updateTemplate(Template template) async {
    final db = await database;
    return db.update('templates', template.toMap(), where: 'name = ?', whereArgs: [template.name]);
  }

  Future<int> deleteTemplate(String name) async {
    final db = await database;
    // Delete template and associated shapes
    await deleteShapes(templateName: name);
    return db.delete('templates', where: 'name = ?', whereArgs: [name]);
  }

  /// Helper method untuk insert template default
  /// Menggunakan DatabaseHelper untuk insert data default
  Future<bool> insertDefaultTemplateData() async {
    return await DatabaseHelper.insertDefaultTemplate();
  }

  /// Helper method untuk initialize database dengan data default
  /// Akan mengecek apakah data default sudah ada, jika belum akan insert
  Future<void> initializeDefaultData() async {
    await DatabaseHelper.initializeWithDefaultData();
  }
}

class ManualSegmentationPage extends StatefulWidget {
  const ManualSegmentationPage({super.key});

  @override
  State<ManualSegmentationPage> createState() => _ManualSegmentationPageState();
}

class _ManualSegmentationPageState extends State<ManualSegmentationPage> with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  Size? _imageSize; // ukuran asli image
  final List<SegShape> _shapes = [];
  final List<SegShape> _undoStack = [];
  final List<SegShape> _redoStack = [];

  // UI state
  String _selectedShapeType = 'rect';
  Offset? _dragStart;
  Offset? _dragCurrent;
  String _currentTemplateName = 'default';

  // scale & offset saat render
  double _scale = 1.0;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  
  // Interaction state for editing existing shapes
  int? _activeShapeIndex;
  String? _activeResizeEdge; // 'move', 'left', 'right', 'top', 'bottom', 'topLeft', 'topRight', 'bottomLeft', 'bottomRight'
  Offset? _lastPanLocal;
  static const double _edgeHitMargin = 12.0;

  // Shape selection and mode state
  int? _selectedShapeIndex;
  String _interactionMode = 'create'; // 'create', 'move', 'resize'

  // Template management state
  late TabController _tabController;
  List<Template> _templates = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTemplates();
    // Pastikan template default tersedia dan langsung dimuat ke editor
    Future.microtask(() async {
      try {
        final existing = await ShapeDatabase.instance.getTemplate('default');
        if (existing == null) {
          await DatabaseHelper.insertDefaultTemplate();
        }
        await _loadTemplate('default');
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    try {
      // Hanya muat template 'default'
      final t = await ShapeDatabase.instance.getTemplate('default');
      setState(() {
        _templates = t != null ? [t] : [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading templates: $e')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    final file = File(xfile.path);
    final bytes = await file.readAsBytes();
    ui.decodeImageFromList(bytes, (ui.Image decoded) {
      if (!mounted) {
        decoded.dispose();
        return;
      }
      setState(() {
        _imageFile = file;
        _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
        _scale = 1.0;
        _offsetX = 0.0;
        _offsetY = 0.0;
        _shapes.clear();
        _undoStack.clear();
        _redoStack.clear();
      });
      decoded.dispose();
    });
  }

  void _onPanStart(DragStartDetails details) {
    if (_imageFile == null || _imageSize == null) return;
    final local = details.localPosition;

    // Try to hit-test existing shapes in reverse order (top-most first)
    int? hitIndex;
    String? hitAction;
    for (int i = _shapes.length - 1; i >= 0; i--) {
      final rect = _rectFromShape(_shapes[i]);
      if (rect.contains(local)) {
        // If in create mode, select the shape and show buttons
        if (_interactionMode == 'create') {
          setState(() {
            _selectedShapeIndex = i;
          });
          return;
        }
        
        // If in move mode, always set to move
        if (_interactionMode == 'move') {
          hitAction = 'move';
          hitIndex = i;
          break;
        }
        
        // If in resize mode, detect edges for resize
        if (_interactionMode == 'resize') {
          final nearLeft = (local.dx - rect.left).abs() <= _edgeHitMargin && local.dy >= rect.top && local.dy <= rect.bottom;
          final nearRight = (local.dx - rect.right).abs() <= _edgeHitMargin && local.dy >= rect.top && local.dy <= rect.bottom;
          final nearTop = (local.dy - rect.top).abs() <= _edgeHitMargin && local.dx >= rect.left && local.dx <= rect.right;
          final nearBottom = (local.dy - rect.bottom).abs() <= _edgeHitMargin && local.dx >= rect.left && local.dx <= rect.right;
          if (nearLeft && nearTop) {
            hitAction = 'topLeft';
          } else if (nearRight && nearTop) {
            hitAction = 'topRight';
          } else if (nearLeft && nearBottom) {
            hitAction = 'bottomLeft';
          } else if (nearRight && nearBottom) {
            hitAction = 'bottomRight';
          } else if (nearLeft) {
            hitAction = 'left';
          } else if (nearRight) {
            hitAction = 'right';
          } else if (nearTop) {
            hitAction = 'top';
          } else if (nearBottom) {
            hitAction = 'bottom';
          } else {
            hitAction = 'move'; // fallback to move if not near edges
          }
          hitIndex = i;
          break;
        }
      }
    }

    if (hitIndex != null && (_interactionMode == 'move' || _interactionMode == 'resize')) {
      // Edit existing shape instead of creating a new one
      _activeShapeIndex = hitIndex;
      _activeResizeEdge = hitAction;
      _lastPanLocal = local;
      _dragStart = null;
      _dragCurrent = null;
      setState(() {});
      return;
    }

    // If clicked outside shapes in create mode, deselect
    if (_interactionMode == 'create') {
      setState(() {
        _selectedShapeIndex = null;
      });
    }

    // No shape hit and in create mode: start drawing a new shape
    if (_interactionMode == 'create') {
      _dragStart = local;
      _dragCurrent = local;
      setState(() {});
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_imageFile == null || _imageSize == null) return;

    // If editing an existing shape
    if (_activeShapeIndex != null && _lastPanLocal != null && _activeResizeEdge != null) {
      final local = details.localPosition;
      final deltaLocal = local - _lastPanLocal!;
      _lastPanLocal = local;

      final s = _shapes[_activeShapeIndex!];
      final imgW = _imageSize!.width;
      final imgH = _imageSize!.height;

      double newX = s.x;
      double newY = s.y;
      double newW = s.width;
      double newH = s.height;
      double? newRX = s.radiusX;
      double? newRY = s.radiusY;

      // Convert delta to image space
      final dxImg = deltaLocal.dx / _scale;
      final dyImg = deltaLocal.dy / _scale;

      // Helper to clamp values to image bounds
      void clampRect() {
        // For ellipse/circle, interpret x,y as center, width/height as diameters
        if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
          final halfW = newW / 2;
          final halfH = newH / 2;
          newX = newX.clamp(halfW, imgW - halfW);
          newY = newY.clamp(halfH, imgH - halfH);
          newW = newW.clamp(4.0, imgW.toDouble());
          newH = newH.clamp(4.0, imgH.toDouble());
        } else {
          newW = newW.clamp(4.0, imgW.toDouble());
          newH = newH.clamp(4.0, imgH.toDouble());
          newX = newX.clamp(0.0, imgW - newW);
          newY = newY.clamp(0.0, imgH - newH);
        }
      }

      switch (_activeResizeEdge) {
        case 'move':
          if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
            newX += dxImg;
            newY += dyImg;
          } else {
            newX += dxImg;
            newY += dyImg;
          }
          break;
        case 'left':
          if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
            // Resize horizontally via radius
            newW -= dxImg;
            if (s.shapeType == 'circle') {
              newH = newW; // keep circle
            }
            newRX = newW / 2;
            newRY = (s.shapeType == 'circle') ? newW / 2 : newH / 2;
          } else {
            newX += dxImg;
            newW -= dxImg;
          }
          break;
        case 'right':
          if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
            newW += dxImg;
            if (s.shapeType == 'circle') {
              newH = newW;
            }
            newRX = newW / 2;
            newRY = (s.shapeType == 'circle') ? newW / 2 : newH / 2;
          } else {
            newW += dxImg;
          }
          break;
        case 'top':
          if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
            newH -= dyImg;
            if (s.shapeType == 'circle') {
              newW = newH;
            }
            newRX = (s.shapeType == 'circle') ? newH / 2 : newW / 2;
            newRY = newH / 2;
          } else {
            newY += dyImg;
            newH -= dyImg;
          }
          break;
        case 'bottom':
          if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
            newH += dyImg;
            if (s.shapeType == 'circle') {
              newW = newH;
            }
            newRX = (s.shapeType == 'circle') ? newH / 2 : newW / 2;
            newRY = newH / 2;
          } else {
            newH += dyImg;
          }
          break;
        case 'topLeft':
          if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
            newW -= dxImg;
            newH -= dyImg;
            if (s.shapeType == 'circle') {
              final side = math.min(newW, newH);
              newW = side;
              newH = side;
            }
            newRX = newW / 2;
            newRY = newH / 2;
          } else {
            newX += dxImg;
            newY += dyImg;
            newW -= dxImg;
            newH -= dyImg;
          }
          break;
        case 'topRight':
          if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
            newW += dxImg;
            newH -= dyImg;
            if (s.shapeType == 'circle') {
              final side = math.min(newW, newH);
              newW = side;
              newH = side;
            }
            newRX = newW / 2;
            newRY = newH / 2;
          } else {
            newY += dyImg;
            newW += dxImg;
            newH -= dyImg;
          }
          break;
        case 'bottomLeft':
          if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
            newW -= dxImg;
            newH += dyImg;
            if (s.shapeType == 'circle') {
              final side = math.min(newW, newH);
              newW = side;
              newH = side;
            }
            newRX = newW / 2;
            newRY = newH / 2;
          } else {
            newX += dxImg;
            newW -= dxImg;
            newH += dyImg;
          }
          break;
        case 'bottomRight':
          if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
            newW += dxImg;
            newH += dyImg;
            if (s.shapeType == 'circle') {
              final side = math.min(newW, newH);
              newW = side;
              newH = side;
            }
            newRX = newW / 2;
            newRY = newH / 2;
          } else {
            newW += dxImg;
            newH += dyImg;
          }
          break;
      }

      clampRect();

      // Build updated shape (SegShape is immutable)
      final updated = SegShape(
        templateName: s.templateName,
        shapeType: s.shapeType,
        x: newX,
        y: newY,
        width: newW,
        height: newH,
        radiusX: (s.shapeType == 'circle' || s.shapeType == 'ellipse') ? newRX : null,
        radiusY: (s.shapeType == 'circle' || s.shapeType == 'ellipse') ? newRY : null,
        rotation: s.rotation,
        imageWidth: s.imageWidth,
        imageHeight: s.imageHeight,
        imagePath: s.imagePath,
      );

      _shapes[_activeShapeIndex!] = updated;
      setState(() {});
      return;
    }

    // Default behavior: drawing new shape preview
    if (_dragStart == null) return;
    if (_interactionMode == 'create') {
      _dragCurrent = details.localPosition;
      setState(() {});
    }
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_imageFile == null || _imageSize == null) return;

    // If editing existing shape, just end the interaction
    if (_activeShapeIndex != null) {
      _activeShapeIndex = null;
      _activeResizeEdge = null;
      _lastPanLocal = null;
      setState(() {});
      return;
    }

    if (_dragStart == null || _dragCurrent == null || _interactionMode != 'create') return;

    // Hitung koordinat di pixel asli: transform balik dari canvas (yang sudah scale/offset) ke image asli
    final imgW = _imageSize!.width;
    final imgH = _imageSize!.height;

    final startCanvas = _dragStart!;
    final endCanvas = _dragCurrent!;

    // transform canvas -> image
    double toImageX(double canvasX) => (canvasX - _offsetX) / _scale;
    double toImageY(double canvasY) => (canvasY - _offsetY) / _scale;

    final ix1 = (toImageX(startCanvas.dx).clamp(0, imgW)).toDouble();
    final iy1 = (toImageY(startCanvas.dy).clamp(0, imgH)).toDouble();
    final ix2 = (toImageX(endCanvas.dx).clamp(0, imgW)).toDouble();
    final iy2 = (toImageY(endCanvas.dy).clamp(0, imgH)).toDouble();

    final left = math.min(ix1, ix2);
    final top = math.min(iy1, iy2);
    final w = (ix2 - ix1).abs();
    final h = (iy2 - iy1).abs();

    SegShape shape;
    switch (_selectedShapeType) {
      case 'rect':
      case 'square':
        // Untuk persegi, pakai sisi min
        final side = _selectedShapeType == 'square' ? math.min(w, h) : w;
        shape = SegShape(
          templateName: _currentTemplateName,
          shapeType: _selectedShapeType,
          x: left,
          y: top,
          width: _selectedShapeType == 'square' ? side : w,
          height: _selectedShapeType == 'square' ? side : h,
          imageWidth: imgW,
          imageHeight: imgH,
          imagePath: _imageFile!.path,
        );
        break;
      case 'circle':
      case 'ellipse':
        final cx = (ix1 + ix2) / 2;
        final cy = (iy1 + iy2) / 2;
        final rx = (ix2 - ix1).abs() / 2;
        final ry = (iy2 - iy1).abs() / 2;
        final r = _selectedShapeType == 'circle' ? math.min(rx, ry) : rx;
        shape = SegShape(
          templateName: _currentTemplateName,
          shapeType: _selectedShapeType,
          x: cx,
          y: cy,
          width: 2 * r,
          height: 2 * (_selectedShapeType == 'circle' ? r : ry),
          radiusX: r,
          radiusY: _selectedShapeType == 'circle' ? r : ry,
          rotation: 0,
          imageWidth: imgW,
          imageHeight: imgH,
          imagePath: _imageFile!.path,
        );
        break;
      default:
        _dragStart = null;
        _dragCurrent = null;
        return;
    }

    // Cegah penambahan shape yang menumpuk (overlap) di atas shape lain
    Rect newBounds;
    if (shape.shapeType == 'circle' || shape.shapeType == 'ellipse') {
      newBounds = Rect.fromCenter(
        center: Offset(shape.x, shape.y),
        width: shape.width,
        height: shape.height,
      );
    } else {
      newBounds = Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);
    }
    bool overlapsExisting = _shapes.any((s) {
      Rect b;
      if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
        b = Rect.fromCenter(center: Offset(s.x, s.y), width: s.width, height: s.height);
      } else {
        b = Rect.fromLTWH(s.x, s.y, s.width, s.height);
      }
      return b.overlaps(newBounds) || b.contains(newBounds.topLeft) || b.contains(newBounds.bottomRight) || newBounds.contains(b.topLeft) || newBounds.contains(b.bottomRight);
    });

    if (overlapsExisting) {
      // Jangan tambahkan shape baru jika overlap
      _dragStart = null;
      _dragCurrent = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shape tidak boleh di atas shape lain')));
      }
      setState(() {});
      return;
    }

    // Simpan shape baru
    _shapes.add(shape);
    _undoStack.add(shape);
    _redoStack.clear();
    _dragStart = null;
    _dragCurrent = null;
    setState(() {});
  }

  // Hitung posisi render di canvas berdasarkan scale + offset dari data shape (pixel asli)
  Rect _rectFromShape(SegShape s) {
    if (s.shapeType == 'circle' || s.shapeType == 'ellipse') {
      final cx = s.x * _scale + _offsetX;
      final cy = s.y * _scale + _offsetY;
      final rx = (s.radiusX ?? s.width / 2) * _scale;
      final ry = (s.radiusY ?? s.height / 2) * _scale;
      return Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);
    }
    final left = s.x * _scale + _offsetX;
    final top = s.y * _scale + _offsetY;
    final w = s.width * _scale;
    final h = s.height * _scale;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Segmentasi Manual'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.grid_view), text: 'Templates'),
            Tab(icon: Icon(Icons.edit), text: 'Editor'),
          ],
        ),
        actions: [
          if (_tabController.index == 1) ...[
            PopupMenuButton<String>(
              initialValue: _selectedShapeType,
              onSelected: (v) => setState(() => _selectedShapeType = v),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rect', child: Text('Kotak/Persegi Panjang')),
                PopupMenuItem(value: 'square', child: Text('Persegi')),
                PopupMenuItem(value: 'circle', child: Text('Lingkaran')),
                PopupMenuItem(value: 'ellipse', child: Text('Elips')),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _shapes.isNotEmpty ? _undo : null,
              tooltip: 'Undo',
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: _redoStack.isNotEmpty ? _redo : null,
              tooltip: 'Redo',
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _imageFile != null ? _saveData : null,
              tooltip: 'Simpan Data',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _selectedShapeIndex != null ? _deleteSelectedShape : null,
              tooltip: 'Hapus Shape Terpilih',
            ),
            // IconButton(
            //   icon: const Icon(Icons.layers),
            //   onPressed: () => _loadTemplate('default'),
            //   tooltip: 'Muat Template Default',
            // ),
            // IconButton(
            //   icon: const Icon(Icons.image),
            //   onPressed: _pickImage,
            //   tooltip: 'Pilih Gambar',
            // ),
          ],
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildTemplateGridView(),
          _buildEditorView(),
        ],
      ),
      // floatingActionButton dihapus
    );
  }

  void _deleteSelectedShape() {
    if (_selectedShapeIndex == null) return;
    final removed = _shapes.removeAt(_selectedShapeIndex!);
    _redoStack.add(removed); // simpan di redoStack agar dapat dikembalikan jika perlu
    _selectedShapeIndex = null;
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shape terpilih dihapus')),
      );
    }
  }

  Widget _buildTemplateGridView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Belum ada template',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Buat template pertama Anda',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                _tabController.animateTo(1);
                _pickImage();
              },
              icon: const Icon(Icons.add),
              label: const Text('Buat Template'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTemplates,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.of(context).size.width > MediaQuery.of(context).size.height ? 4 : 2, // 4 columns in landscape, 2 in portrait
            childAspectRatio: 0.8,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: _templates.length,
          itemBuilder: (context, index) {
            final template = _templates[index];
            return _buildTemplateCard(template);
          },
        ),
      ),
    );
  }

  Widget _buildTemplateCard(Template template) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _loadTemplate(template.name),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: template.imagePath.startsWith('assets/')
                    ? Image.asset(
                        template.imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.broken_image, size: 48),
                          );
                        },
                      )
                    : (template.imagePath.startsWith('data:image')
                        ? Image.memory(
                            base64Decode(template.imagePath.split(',').last),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.broken_image, size: 48),
                              );
                            },
                          )
                        : (File(template.imagePath).existsSync()
                            ? Image.file(
                                File(template.imagePath),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Icon(Icons.broken_image, size: 48),
                                  );
                                },
                              )
                            : const Center(
                                child: Icon(Icons.image_not_supported, size: 48),
                              ))),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.category,
                          size: 16,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${template.shapeCount} shapes',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(template.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => _changeTemplateImage(template),
                          icon: const Icon(Icons.image),
                          label: const Text('Ubah Gambar'),
                        ),
                      ],
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

  Future<void> _changeTemplateImage(Template template) async {
    try {
      final xfile = await _picker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return;

      // Baca bytes gambar yang dipilih
      Uint8List bytes;
      File? pickedFile;
      if (kIsWeb) {
        bytes = await xfile.readAsBytes();
      } else {
        pickedFile = File(xfile.path);
        bytes = await pickedFile.readAsBytes();
      }

      // Decode untuk mendapatkan ukuran gambar baru
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final newW = frame.image.width.toDouble();
      final newH = frame.image.height.toDouble();
      frame.image.dispose();

      // Tentukan lokasi/path penyimpanan sesuai platform
      String savedImagePath;
      if (kIsWeb) {
        // Di web, gunakan Data URI base64 agar bisa dirender tanpa File IO
        final dotIndex = xfile.name.lastIndexOf('.');
        final ext = dotIndex != -1 ? xfile.name.substring(dotIndex + 1).toLowerCase() : 'png';
        final mime = (ext == 'png') ? 'image/png' : 'image/jpeg';
        final b64 = base64Encode(bytes);
        savedImagePath = 'data:$mime;base64,$b64';
      } else {
        // Simpan ke folder aplikasi (mobile/desktop)
        final appDir = await getApplicationDocumentsDirectory();
        final templatesDir = Directory('${appDir.path}/templates');
        if (!await templatesDir.exists()) {
          await templatesDir.create(recursive: true);
        }
        final dotIndex = xfile.path.lastIndexOf('.');
        final ext = dotIndex != -1 ? xfile.path.substring(dotIndex) : '.jpg';
        savedImagePath = '${templatesDir.path}/${template.name}$ext';
        final destFile = File(savedImagePath);
        if (await destFile.exists()) {
          await destFile.delete();
        }
        await destFile.writeAsBytes(bytes, flush: true);
      }

      // Update template
      final updatedTemplate = Template(
        name: template.name,
        imagePath: savedImagePath,
        createdAt: template.createdAt,
        shapeCount: template.shapeCount,
        description: template.description,
      );
      await ShapeDatabase.instance.updateTemplate(updatedTemplate);

      // Ambil shapes lama, skala sesuai ukuran baru, lalu replace di DB
      final oldShapes = await ShapeDatabase.instance.getShapes(templateName: template.name);
      await ShapeDatabase.instance.deleteShapes(templateName: template.name);

      for (final s in oldShapes) {
        final scaleX = newW / s.imageWidth;
        final scaleY = newH / s.imageHeight;

        final updatedShape = SegShape(
          templateName: s.templateName,
          shapeType: s.shapeType,
          x: s.x * scaleX,
          y: s.y * scaleY,
          width: s.width * scaleX,
          height: s.height * scaleY,
          radiusX: s.radiusX != null ? s.radiusX! * scaleX : null,
          radiusY: s.radiusY != null ? s.radiusY! * scaleY : null,
          rotation: s.rotation,
          imageWidth: newW,
          imageHeight: newH,
          imagePath: savedImagePath,
        );

        await ShapeDatabase.instance.insertShape(updatedShape);
      }

      await _loadTemplates();

      // Jika template yang diubah sedang aktif di editor, muat ulang agar gambar baru tampil
      if (_currentTemplateName == template.name) {
        // Clear image cache untuk file lama agar gambar baru tampil
        if (!kIsWeb && pickedFile != null) {
          final FileImage fileImage = FileImage(File(savedImagePath));
          await fileImage.evict();
        }

        // Load ulang template dengan gambar baru
        await _loadTemplate(template.name);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gambar template berhasil diubah')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengubah gambar: $e')),
        );
      }
    }
  }

  Widget _buildEditorView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth;
        final ch = constraints.maxHeight;

        Widget content;
        if (_imageFile == null || _imageSize == null) {
          content = Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'Pilih gambar untuk mulai',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image),
                  label: const Text('Pilih Gambar'),
                ),
              ],
            ),
          );
        } else {
          // Hitung scale & offset agar gambar muat ke ruang tersedia (contain)
          final imgW = _imageSize!.width;
          final imgH = _imageSize!.height;
          final scaleX = cw / imgW;
          final scaleY = ch / imgH;
          _scale = math.min(scaleX, scaleY);
          final displayW = imgW * _scale;
          final displayH = imgH * _scale;
          _offsetX = (cw - displayW) / 2;
          _offsetY = (ch - displayH) / 2;

          content = GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Stack(
              children: [
                Positioned(
                  left: _offsetX,
                  top: _offsetY,
                  width: displayW,
                  height: displayH,
                  child: Image.file(
                    _imageFile!,
                    key: ValueKey(_imageFile!.path), // Force rebuild saat path berubah
                    fit: BoxFit.fill,
                    gaplessPlayback: false, // Disable cache untuk memuat gambar baru
                  ),
                ),
                // render shapes
                ..._shapes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final s = entry.value;
                  final rect = _rectFromShape(s);
                  final isSelected = _selectedShapeIndex == index;
                  
                  return Positioned(
                    left: rect.left,
                    top: rect.top,
                    width: rect.width,
                    height: rect.height,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: SegShapePainter(
                          shapeType: s.shapeType,
                          fillColor: isSelected 
                              ? Colors.blueAccent.withValues(alpha: 0.25)
                              : Colors.redAccent.withValues(alpha: 0.15),
                          strokeColor: isSelected 
                              ? Colors.blueAccent
                              : Colors.redAccent,
                          strokeWidth: isSelected ? 3 : 2,
                        ),
                      ),
                    ),
                  );
                }),
                // Show move and drag buttons for selected shape
                if (_selectedShapeIndex != null) ...[
                  Builder(
                    builder: (context) {
                      final selectedShape = _shapes[_selectedShapeIndex!];
                      final rect = _rectFromShape(selectedShape);
                      
                      return Positioned(
                        left: rect.left + rect.width / 2 - 60,
                        top: rect.top - 50,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    setState(() {
                                      _interactionMode = 'move';
                                    });
                                  },
                                  onDoubleTap: () {
                                    _showCreateNewShapeNotification();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.open_with,
                                          size: 16,
                                          color: _interactionMode == 'move' 
                                              ? Colors.blue 
                                              : Colors.grey[700],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Geser',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _interactionMode == 'move' 
                                                ? Colors.blue 
                                                : Colors.grey[700],
                                            fontWeight: _interactionMode == 'move' 
                                                ? FontWeight.bold 
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    setState(() {
                                      _interactionMode = 'resize';
                                    });
                                  },
                                  onDoubleTap: () {
                                    _showCreateNewShapeNotification();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.crop_free,
                                          size: 16,
                                          color: _interactionMode == 'resize' 
                                              ? Colors.green 
                                              : Colors.grey[700],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Tarik',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _interactionMode == 'resize' 
                                                ? Colors.green 
                                                : Colors.grey[700],
                                            fontWeight: _interactionMode == 'resize' 
                                                ? FontWeight.bold 
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: _deleteSelectedShape,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.delete_outline,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Hapus',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  // Show corner drag handles when in resize mode
                  if (_interactionMode == 'resize') ...[
                    Builder(
                      builder: (context) {
                        final selectedShape = _shapes[_selectedShapeIndex!];
                        final rect = _rectFromShape(selectedShape);
                        const handleSize = 12.0;
                        
                        return Stack(
                          children: [
                            // Top-left corner handle
                            Positioned(
                              left: rect.left - handleSize / 2,
                              top: rect.top - handleSize / 2,
                              child: GestureDetector(
                                onPanStart: (details) {
                                  _activeShapeIndex = _selectedShapeIndex!;
                                  _activeResizeEdge = 'topLeft';
                                  _lastPanLocal = details.localPosition + Offset(rect.left - handleSize / 2, rect.top - handleSize / 2);
                                },
                                onPanUpdate: (details) {
                                  if (_activeShapeIndex != null && _activeResizeEdge != null) {
                                    _onPanUpdate(DragUpdateDetails(
                                      localPosition: details.localPosition + Offset(rect.left - handleSize / 2, rect.top - handleSize / 2),
                                      delta: details.delta,
                                      globalPosition: details.globalPosition,
                                    ));
                                  }
                                },
                                onPanEnd: (details) {
                                  _onPanEnd(DragEndDetails(
                                    localPosition: details.localPosition + Offset(rect.left - handleSize / 2, rect.top - handleSize / 2),
                                  ));
                                },
                                child: Container(
                                  width: handleSize,
                                  height: handleSize,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.green, width: 2),
                                    borderRadius: BorderRadius.circular(handleSize / 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 2,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Top-right corner handle
                            Positioned(
                              left: rect.right - handleSize / 2,
                              top: rect.top - handleSize / 2,
                              child: GestureDetector(
                                onPanStart: (details) {
                                  _activeShapeIndex = _selectedShapeIndex!;
                                  _activeResizeEdge = 'topRight';
                                  _lastPanLocal = details.localPosition + Offset(rect.right - handleSize / 2, rect.top - handleSize / 2);
                                },
                                onPanUpdate: (details) {
                                  if (_activeShapeIndex != null && _activeResizeEdge != null) {
                                    _onPanUpdate(DragUpdateDetails(
                                      localPosition: details.localPosition + Offset(rect.right - handleSize / 2, rect.top - handleSize / 2),
                                      delta: details.delta,
                                      globalPosition: details.globalPosition,
                                    ));
                                  }
                                },
                                onPanEnd: (details) {
                                  _onPanEnd(DragEndDetails(
                                    localPosition: details.localPosition + Offset(rect.right - handleSize / 2, rect.top - handleSize / 2),
                                  ));
                                },
                                child: Container(
                                  width: handleSize,
                                  height: handleSize,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.green, width: 2),
                                    borderRadius: BorderRadius.circular(handleSize / 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 2,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Bottom-left corner handle
                            Positioned(
                              left: rect.left - handleSize / 2,
                              top: rect.bottom - handleSize / 2,
                              child: GestureDetector(
                                onPanStart: (details) {
                                  _activeShapeIndex = _selectedShapeIndex!;
                                  _activeResizeEdge = 'bottomLeft';
                                  _lastPanLocal = details.localPosition + Offset(rect.left - handleSize / 2, rect.bottom - handleSize / 2);
                                },
                                onPanUpdate: (details) {
                                  if (_activeShapeIndex != null && _activeResizeEdge != null) {
                                    _onPanUpdate(DragUpdateDetails(
                                      localPosition: details.localPosition + Offset(rect.left - handleSize / 2, rect.bottom - handleSize / 2),
                                      delta: details.delta,
                                      globalPosition: details.globalPosition,
                                    ));
                                  }
                                },
                                onPanEnd: (details) {
                                  _onPanEnd(DragEndDetails(
                                    localPosition: details.localPosition + Offset(rect.left - handleSize / 2, rect.bottom - handleSize / 2),
                                  ));
                                },
                                child: Container(
                                  width: handleSize,
                                  height: handleSize,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.green, width: 2),
                                    borderRadius: BorderRadius.circular(handleSize / 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 2,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Bottom-right corner handle
                            Positioned(
                              left: rect.right - handleSize / 2,
                              top: rect.bottom - handleSize / 2,
                              child: GestureDetector(
                                onPanStart: (details) {
                                  _activeShapeIndex = _selectedShapeIndex!;
                                  _activeResizeEdge = 'bottomRight';
                                  _lastPanLocal = details.localPosition + Offset(rect.right - handleSize / 2, rect.bottom - handleSize / 2);
                                },
                                onPanUpdate: (details) {
                                  if (_activeShapeIndex != null && _activeResizeEdge != null) {
                                    _onPanUpdate(DragUpdateDetails(
                                      localPosition: details.localPosition + Offset(rect.right - handleSize / 2, rect.bottom - handleSize / 2),
                                      delta: details.delta,
                                      globalPosition: details.globalPosition,
                                    ));
                                  }
                                },
                                onPanEnd: (details) {
                                  _onPanEnd(DragEndDetails(
                                    localPosition: details.localPosition + Offset(rect.right - handleSize / 2, rect.bottom - handleSize / 2),
                                  ));
                                },
                                child: Container(
                                  width: handleSize,
                                  height: handleSize,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.green, width: 2),
                                    borderRadius: BorderRadius.circular(handleSize / 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 2,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
                // preview shape selama drag
                if (_dragStart != null && _dragCurrent != null)
                  Positioned(
                    left: math.min(_dragStart!.dx, _dragCurrent!.dx),
                    top: math.min(_dragStart!.dy, _dragCurrent!.dy),
                    width: (_selectedShapeType == 'square' || _selectedShapeType == 'circle')
                        ? math.min((_dragCurrent!.dx - _dragStart!.dx).abs(), (_dragCurrent!.dy - _dragStart!.dy).abs())
                        : (_dragCurrent!.dx - _dragStart!.dx).abs(),
                    height: (_selectedShapeType == 'square' || _selectedShapeType == 'circle')
                        ? math.min((_dragCurrent!.dx - _dragStart!.dx).abs(), (_dragCurrent!.dy - _dragStart!.dy).abs())
                        : (_dragCurrent!.dy - _dragStart!.dy).abs(),
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: SegShapePainter(
                          shapeType: _selectedShapeType,
                          fillColor: Colors.blueAccent.withValues(alpha: 0.15),
                          strokeColor: Colors.blueAccent,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
              
              ],
            ),
          );
        }

        return content;
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Hari ini';
    } else if (difference.inDays == 1) {
      return 'Kemarin';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} hari lalu';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _editTemplate(Template template) async {
    final nameController = TextEditingController(text: template.name);
    final descController = TextEditingController(text: template.description ?? '');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Template',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Deskripsi (opsional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, {
                  'name': name,
                  'description': descController.text.trim(),
                });
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result != null) {
      final updatedTemplate = Template(
        name: result['name']!,
        imagePath: template.imagePath,
        createdAt: template.createdAt,
        shapeCount: template.shapeCount,
        description: result['description']!.isEmpty ? null : result['description'],
      );

      try {
        await ShapeDatabase.instance.updateTemplate(updatedTemplate);
        await _loadTemplates();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Template berhasil diperbarui')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating template: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteTemplate(Template template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Template'),
        content: Text('Apakah Anda yakin ingin menghapus template "${template.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Delete image file only if it's not an asset path
        if (!template.imagePath.startsWith('assets/')) {
          final imageFile = File(template.imagePath);
          if (await imageFile.exists()) {
            await imageFile.delete();
          }
        }

        await ShapeDatabase.instance.deleteTemplate(template.name);
        await _loadTemplates();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Template berhasil dihapus')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting template: $e')),
          );
        }
      }
    }
  }

  Future<void> _loadTemplate(String templateName) async {
    try {
      // Load template data
      final shapes = await ShapeDatabase.instance.getShapes(templateName: templateName);
      if (shapes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Template tidak memiliki data')),
          );
        }
        return;
      }
      // Ambil imagePath dari tabel templates jika tersedia, fallback ke shapes
      String imagePath;
      try {
        final tpl = await ShapeDatabase.instance.getTemplate(templateName);
        if (tpl != null && tpl.imagePath.isNotEmpty) {
          imagePath = tpl.imagePath;
        } else {
          imagePath = shapes.first.imagePath;
        }
      } catch (_) {
        imagePath = shapes.first.imagePath;
      }
      Uint8List bytes;
      File? imageFile;

      if (imagePath.startsWith('assets/')) {
        // Muat dari assets dan salin ke storage aplikasi agar editor dapat memakai File
        final ByteData data = await rootBundle.load(imagePath);
        bytes = data.buffer.asUint8List();

        final appDir = await getApplicationDocumentsDirectory();
        final templatesDir = Directory('${appDir.path}/templates');
        if (!await templatesDir.exists()) {
          await templatesDir.create(recursive: true);
        }
        final savedImagePath = '${templatesDir.path}/$templateName.png';
        imageFile = File(savedImagePath);
        await imageFile.writeAsBytes(bytes, flush: true);
      } else if (imagePath.startsWith('data:image')) {
        // Muat dari data URI base64 (khusus web)
        final b64 = imagePath.split(',').last;
        bytes = base64Decode(b64);
        imageFile = null; // Tidak ada File fisik di web
      } else {
        imageFile = File(imagePath);
        if (!await imageFile.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File gambar tidak ditemukan')),
            );
          }
          return;
        }
        // Evict cache untuk memastikan gambar terbaru dimuat
        final FileImage fileImage = FileImage(imageFile);
        await fileImage.evict();
        bytes = await imageFile.readAsBytes();
      }

      // Decode dan set state
      ui.decodeImageFromList(bytes, (ui.Image decoded) {
        if (!mounted) {
          decoded.dispose();
          return;
        }
        setState(() {
          // Di web, imageFile bisa null; editor tetap bekerja dengan bytes/size
          if (imageFile != null) {
            _imageFile = imageFile;
          } else {
            _imageFile = null;
          }
          _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
          _shapes
            ..clear()
            ..addAll(shapes);
          _undoStack.clear();
          _redoStack.clear();
          _currentTemplateName = templateName;
          _scale = 1.0;
          _offsetX = 0.0;
          _offsetY = 0.0;
        });
        decoded.dispose();

        // Pindah ke tab editor
        _tabController.animateTo(1);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Template "$templateName" dimuat')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading template: $e')),
        );
      }
    }
  }

  void _undo() {
    if (_shapes.isEmpty) return;
    final last = _shapes.removeLast();
    _redoStack.add(last);
    setState(() {});
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final s = _redoStack.removeLast();
    _shapes.add(s);
    setState(() {});
  }

  Future<void> _saveData() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih gambar terlebih dahulu')));
      return;
    }
    // Paksa menggunakan nama template 'default'
    const title = 'default';
    _currentTemplateName = title;

    // Salin gambar ke penyimpanan aplikasi agar template menyimpan gambarnya juga
    final appDir = await getApplicationDocumentsDirectory();
    final templatesDir = Directory('${appDir.path}/templates');
    if (!await templatesDir.exists()) {
      await templatesDir.create(recursive: true);
    }
    final origPath = _imageFile!.path;
    final dotIndex = origPath.lastIndexOf('.');
    final ext = dotIndex != -1 ? origPath.substring(dotIndex) : '.jpg';
    const safeTitle = 'default';
    final savedImagePath = '${templatesDir.path}/$safeTitle$ext';
    final destFile = File(savedImagePath);
    // Jika path sumber sama dengan path tujuan, jangan hapus/copy (hindari menghapus sumber)
    if (origPath != savedImagePath) {
      if (await destFile.exists()) {
        await destFile.delete();
      }
      try {
        await _imageFile!.copy(savedImagePath);
      } catch (_) {
        // Fallback: tulis bytes secara manual jika copy gagal
        final bytes = await _imageFile!.readAsBytes();
        await destFile.writeAsBytes(bytes, flush: true);
      }
    }

    // Save template to database
    // Update template default jika sudah ada, jika belum insert
    final existing = await ShapeDatabase.instance.getTemplate(title);
    final template = Template(
      name: title,
      imagePath: savedImagePath,
      createdAt: existing?.createdAt ?? DateTime.now(),
      shapeCount: _shapes.length,
      description: existing?.description,
    );
    
    // Log data template yang akan disimpan
    developer.log('=== SAVING TEMPLATE DATA ===', name: 'ManualSegmentationPage');
    developer.log('Template Name: ${template.name}', name: 'ManualSegmentationPage');
    developer.log('Image Path: ${template.imagePath}', name: 'ManualSegmentationPage');
    developer.log('Created At: ${template.createdAt}', name: 'ManualSegmentationPage');
    developer.log('Shape Count: ${template.shapeCount}', name: 'ManualSegmentationPage');
    developer.log('Template Map: ${template.toMap()}', name: 'ManualSegmentationPage');
    
    if (existing == null) {
      await ShapeDatabase.instance.insertTemplate(template);
    } else {
      await ShapeDatabase.instance.updateTemplate(template);
    }

    // Hapus data lama untuk template + gambar tersalin
    // Hapus semua shapes lama untuk template 'default'
    await ShapeDatabase.instance.deleteShapes(templateName: title);
    
    developer.log('=== SAVING SHAPES DATA ===', name: 'ManualSegmentationPage');
    developer.log('Total shapes to save: ${_shapes.length}', name: 'ManualSegmentationPage');
    
    for (int i = 0; i < _shapes.length; i++) {
      final s = _shapes[i];
      final s2 = SegShape(
        templateName: title,
        shapeType: s.shapeType,
        x: s.x,
        y: s.y,
        width: s.width,
        height: s.height,
        radiusX: s.radiusX,
        radiusY: s.radiusY,
        rotation: s.rotation,
        imageWidth: s.imageWidth,
        imageHeight: s.imageHeight,
        imagePath: savedImagePath,
      );
      
      // Log data shape yang akan disimpan
      developer.log('--- Shape ${i + 1} ---', name: 'ManualSegmentationPage');
      developer.log('Shape Type: ${s2.shapeType}', name: 'ManualSegmentationPage');
      developer.log('Position: (${s2.x}, ${s2.y})', name: 'ManualSegmentationPage');
      developer.log('Size: ${s2.width} x ${s2.height}', name: 'ManualSegmentationPage');
      developer.log('Radius: (${s2.radiusX}, ${s2.radiusY})', name: 'ManualSegmentationPage');
      developer.log('Rotation: ${s2.rotation}', name: 'ManualSegmentationPage');
      developer.log('Image Size: ${s2.imageWidth} x ${s2.imageHeight}', name: 'ManualSegmentationPage');
      developer.log('Normalized Position: (${s2.normalizedX}, ${s2.normalizedY})', name: 'ManualSegmentationPage');
      developer.log('Normalized Size: ${s2.normalizedWidth} x ${s2.normalizedHeight}', name: 'ManualSegmentationPage');
      developer.log('Shape Map: ${s2.toMap()}', name: 'ManualSegmentationPage');
      
      await ShapeDatabase.instance.insertShape(s2);
    }
    
    // Refresh templates list
    await _loadTemplates();
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data dan gambar disimpan untuk "default"')));
  }

  void _showCreateNewShapeNotification() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Klik dua kali untuk membuat shape baru'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.blue,
      ),
    );
    
    // Reset to create mode after showing notification
    setState(() {
      _interactionMode = 'create';
      _selectedShapeIndex = null;
    });
  }
}