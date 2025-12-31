import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Launches the Google Maps application for a specific coordinate.
Future<void> openMap(double lat, double lng) async {
  final url = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
  if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Utility function to launch any given URL in an external application (Browser/TikTok/Instagram).
Future<void> launchURL(String urlString) async {
  final Uri url = Uri.parse(urlString);
  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } else {
    debugPrint('Could not launch $urlString');
  }
}