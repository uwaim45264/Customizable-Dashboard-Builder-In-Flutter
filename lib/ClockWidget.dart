import 'package:flutter/material.dart';

class ClockWidget extends StatelessWidget {
  final Size size;

  ClockWidget({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blue, Colors.purple]),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
      ),
      child: Center(
        child: StreamBuilder(
          stream: Stream.periodic(Duration(seconds: 1)),
          builder: (BuildContext context, snapshot) {
            return Text(
              DateTime.now().toString().substring(11, 19),
              style: TextStyle(color: Colors.white, fontSize: size.height * 0.15),
            );
          },
        ),
      ),
    );
  }
}
