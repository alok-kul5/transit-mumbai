import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../state/app_state.dart';

/// Asks for one location fix and stores it. The position never leaves the device.
Future<void> locate(TransitState state) async {
  state.setLocating();
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      state.setLocationError('Location is turned off on this device.');
      return;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      state.setLocationError('Location permission was not given.');
      return;
    }
    const limit = Duration(seconds: 15);
    // On Android, the platform's own location manager: a station is hundreds of
    // metres wide, so there is no need for Play Services' accuracy prompt.
    final settings = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(accuracy: LocationAccuracy.medium, forceLocationManager: true, timeLimit: limit)
        : const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: limit);
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(locationSettings: settings);
    } catch (_) {
      if (!kIsWeb) pos = await Geolocator.getLastKnownPosition(forceAndroidLocationManager: true);
    }
    if (pos == null) {
      state.setLocationError('Could not find your location.');
      return;
    }
    state.setHere(pos.latitude, pos.longitude);
  } catch (e) {
    state.setLocationError('Could not find your location.');
  }
}
