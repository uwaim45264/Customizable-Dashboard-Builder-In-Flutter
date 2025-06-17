import 'package:flutter/material.dart';

class CalendarWidget extends StatelessWidget {
  final Size size;

  CalendarWidget({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.green, Colors.teal]),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
      ),
      child: Center(
        child: Text(
          DateTime.now().toString().substring(0, 10),
          style: TextStyle(color: Colors.white, fontSize: size.height * 0.12),
        ),
      ),
    );
  }
}