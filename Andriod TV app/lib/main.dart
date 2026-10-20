import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/api_service.dart';
import 'theme/tv_theme.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force Landscape Orientation for Android TV / Google TV
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Immersive full-screen (hide status/navigation bars on TV)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final apiService = ApiService();
  runApp(ShapnoTVApp(apiService: apiService));
}

class ShapnoTVApp extends StatelessWidget {
  final ApiService apiService;

  const ShapnoTVApp({super.key, required this.apiService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shapno TV',
      debugShowCheckedModeBanner: false,
      theme: TVTheme.darkTheme,
      home: TVHomeScreen(apiService: apiService),
    );
  }
}
