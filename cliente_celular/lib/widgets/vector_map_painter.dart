import 'package:flutter/material.dart';
import '../models/order.dart';

class VectorMapPainter extends CustomPainter {
  final Order? activeOrder;
  final List<Order>? allOrders;

  VectorMapPainter({this.activeOrder, this.allOrders});

  double mapX(double x, Size size) => (x / 500.0) * size.width;
  double mapY(double y, Size size) => (y / 400.0) * size.height;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Draw Map Background (Light Grey)
    final bgPaint = Paint()..color = const Color(0xFFF3F4F6);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // 2. Draw subtle Grid
    final gridPaint = Paint()
      ..color = Colors.black.withOpacity(0.02)
      ..strokeWidth = 1.0;
    const double gridSize = 30.0;
    for (double x = 0; x < w; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (double y = 0; y < h; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // 3. Draw Green Park Zone (Eco Green)
    final parkPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.06)
      ..style = PaintingStyle.fill;
    final parkPath = Path()
      ..moveTo(w * 0.45, h * 0.1)
      ..lineTo(w * 0.75, h * 0.1)
      ..lineTo(w * 0.85, h * 0.4)
      ..lineTo(w * 0.55, h * 0.45)
      ..close();
    canvas.drawPath(parkPath, parkPaint);

    // 4. Draw Blue River
    final riverPaint = Paint()
      ..color = const Color(0xFFDBEAFE)
      ..strokeWidth = 8.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final riverPath = Path()
      ..moveTo(-10, h * 0.75)
      ..cubicTo(w * 0.3, h * 0.7, w * 0.6, h * 0.85, w + 10, h * 0.8);
    canvas.drawPath(riverPath, riverPaint);

    // 5. Draw Street Grid Network (Base White Roads)
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;
    
    void drawRoadLine(double x1, double y1, double x2, double y2) {
      canvas.drawLine(
        Offset(mapX(x1, size), mapY(y1, size)),
        Offset(mapX(x2, size), mapY(y2, size)),
        roadPaint,
      );
    }

    drawRoadLine(20, 70, 480, 70);
    drawRoadLine(180, 20, 180, 380);
    drawRoadLine(20, 170, 450, 170);
    drawRoadLine(300, 170, 300, 380);
    drawRoadLine(100, 260, 450, 260);
    drawRoadLine(420, 100, 420, 380);

    // 6. Draw Warehouse Hub (Grey Base)
    _drawMarker(canvas, size, 80, 70, const Color(0xFF374151), 'B');

    // 7. Draw destinations for ALL orders if viewing from Driver overview
    if (allOrders != null) {
      for (final order in allOrders!) {
        if (order.status != 'delivered') {
          final dest = _getDestCoords(order.id);
          final color = _getBrandColor(order.brand);
          _drawMarker(canvas, size, dest['x']!, dest['y']!, color, order.client.isNotEmpty ? order.client[0] : 'C');
          
          // Draw riders for other orders too if they are accepted, in transit, or arrived
          if (order.status == 'accepted' || order.status == 'in_transit' || order.status == 'arrived') {
            final rx = mapX(order.currentX, size);
            final ry = mapY(order.currentY, size);
            canvas.drawCircle(Offset(rx, ry), 8.0, Paint()..color = color.withOpacity(0.15));
            canvas.drawCircle(Offset(rx, ry), 4.5, Paint()..color = color);
            canvas.drawCircle(Offset(rx, ry), 4.5, Paint()..color = Colors.white..strokeWidth = 1.0..style = PaintingStyle.stroke);
          }
        }
      }
    }

    // 8. Draw Active Route Path & Active Rider
    if (activeOrder != null) {
      final order = activeOrder!;
      final brandColor = _getBrandColor(order.brand);
      final routePoints = _getRoutePoints(order.id);
      
      if (routePoints.isNotEmpty) {
        final routeLinePaint = Paint()
          ..color = brandColor.withOpacity(0.8)
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final path = Path()..moveTo(mapX(routePoints[0]['x']!, size), mapY(routePoints[0]['y']!, size));
        for (int i = 1; i < routePoints.length; i++) {
          path.lineTo(mapX(routePoints[i]['x']!, size), mapY(routePoints[i]['y']!, size));
        }
        canvas.drawPath(path, routeLinePaint);
      }

      // Draw active client destination again on top
      final dest = _getDestCoords(order.id);
      _drawMarker(canvas, size, dest['x']!, dest['y']!, brandColor, 'D');

      // Draw active rider in motion or accepted
      if (order.status == 'accepted' || order.status == 'in_transit' || order.status == 'arrived') {
        final rx = mapX(order.currentX, size);
        final ry = mapY(order.currentY, size);

        // Pulse ring
        final pulsePaint = Paint()
          ..color = brandColor.withOpacity(0.2)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(rx, ry), 12.0, pulsePaint);

        // Rider dot
        final riderPaint = Paint()
          ..color = brandColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(rx, ry), 6.0, riderPaint);

        // White outline
        final strokePaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(Offset(rx, ry), 6.0, strokePaint);
      }
    }
  }

  void _drawMarker(Canvas canvas, Size size, double x, double y, Color color, String label) {
    final mx = mapX(x, size);
    final my = mapY(y, size);

    final circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(mx, my), 6.0, circlePaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(mx, my), 6.0, borderPaint);
  }

  Color _getBrandColor(String brand) {
    if (brand.contains('Amazon')) return const Color(0xFFFF9900);
    if (brand.contains('MercadoLibre')) return const Color(0xFF2563EB);
    if (brand.contains('DHL')) return const Color(0xFFCC0000);
    return Colors.blue;
  }

  Map<String, double> _getDestCoords(String id) {
    if (id == 'order-1') return {'x': 420.0, 'y': 310.0};
    if (id == 'order-2') return {'x': 300.0, 'y': 340.0};
    if (id == 'order-3') return {'x': 420.0, 'y': 170.0};
    return {'x': 250.0, 'y': 200.0};
  }

  List<Map<String, double>> _getRoutePoints(String id) {
    if (id == 'order-1') {
      return [
        {'x': 80.0, 'y': 70.0},
        {'x': 180.0, 'y': 70.0},
        {'x': 180.0, 'y': 170.0},
        {'x': 300.0, 'y': 170.0},
        {'x': 300.0, 'y': 260.0},
        {'x': 420.0, 'y': 260.0},
        {'x': 420.0, 'y': 310.0}
      ];
    }
    if (id == 'order-2') {
      return [
        {'x': 80.0, 'y': 70.0},
        {'x': 180.0, 'y': 70.0},
        {'x': 180.0, 'y': 170.0},
        {'x': 300.0, 'y': 170.0},
        {'x': 300.0, 'y': 340.0}
      ];
    }
    if (id == 'order-3') {
      return [
        {'x': 80.0, 'y': 70.0},
        {'x': 180.0, 'y': 70.0},
        {'x': 180.0, 'y': 170.0},
        {'x': 420.0, 'y': 170.0}
      ];
    }
    return [];
  }

  @override
  bool shouldRepaint(covariant VectorMapPainter oldDelegate) => true;
}
