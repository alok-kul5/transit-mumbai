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
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
    );
    state.setHere(pos.latitude, pos.longitude);
  } catch (e) {
    state.setLocationError('Could not find your location.');
  }
}
