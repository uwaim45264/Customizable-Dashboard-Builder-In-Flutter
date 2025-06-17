import 'package:flutter/material.dart';

class WidgetModel {
  final int id;
  String type;
  Offset position;
  double width;
  double height;
  String content;
  Color bgColor;
  double fontSize;
  double rotation;

  WidgetModel({
    required this.id,
    required this.type,
    required this.position,
    required this.width,
    required this.height,
    this.content = '',
    this.bgColor = Colors.blue,
    this.fontSize = 14,
    this.rotation = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'x': position.dx,
      'y': position.dy,
      'width': width,
      'height': height,
      'content': content,
      'bgColor': bgColor.value.toString(),
      'fontSize': fontSize,
      'rotation': rotation,
    };
  }

  factory WidgetModel.fromMap(Map<String, dynamic> map) {
    return WidgetModel(
      id: map['id'],
      type: map['type'],
      position: Offset(map['x'], map['y']),
      width: map['width'],
      height: map['height'],
      content: map['content'] ?? '',
      bgColor: Color(int.parse(map['bgColor'])),
      fontSize: map['fontSize'],
      rotation: map['rotation'] ?? 0,
    );
  }
}