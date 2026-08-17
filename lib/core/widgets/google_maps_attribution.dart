import 'package:flutter/material.dart';

class GoogleMapsAttribution extends StatelessWidget {
  const GoogleMapsAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Google Maps',
      child: const Text(
        'Google Maps',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      ),
    );
  }
}
