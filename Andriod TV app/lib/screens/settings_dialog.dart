import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/tv_theme.dart';
import '../widgets/tv_focus_button.dart';

class TVSettingsDialog extends StatefulWidget {
  final ApiService apiService;

  const TVSettingsDialog({super.key, required this.apiService});

  @override
  State<TVSettingsDialog> createState() => _TVSettingsDialogState();
}

class _TVSettingsDialogState extends State<TVSettingsDialog> {
  late TextEditingController _controller;
  bool _testing = false;
  String _statusText = '';
  Color _statusColor = TVTheme.textSecondary;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.apiService.baseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _testAndSave(String targetUrl) async {
    setState(() {
      _testing = true;
      _controller.text = targetUrl;
      _statusText = 'Probing $targetUrl...';
      _statusColor = TVTheme.textSecondary;
    });

    await widget.apiService.setBaseUrl(targetUrl);

    if (widget.apiService.isConnected) {
      setState(() {
        _testing = false;
        _statusText = '✓ Connected! Discovered ${widget.apiService.movies.length} movies & ${widget.apiService.series.length} series.';
        _statusColor = TVTheme.emerald;
      });
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) Navigator.pop(context);
      });
    } else {
      setState(() {
        _testing = false;
        _statusText = '✗ Connection Failed. Check if "npm run dev" is running on laptop.';
        _statusColor = TVTheme.crimson;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: TVTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: TVTheme.border),
      ),
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.router_outlined, color: TVTheme.emerald, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Local Server Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: TVTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your laptop server address, or select a quick preset below:',
              style: TextStyle(color: TVTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                filled: true,
                fillColor: TVTheme.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: TVTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: TVTheme.emerald, width: 2),
                ),
                prefixIcon: const Icon(Icons.link, color: TVTheme.emerald),
              ),
            ),
            const SizedBox(height: 14),

            // Quick Presets
            const Text(
              'Quick Connect Presets:',
              style: TextStyle(color: TVTheme.textMuted, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPresetChip('📺 Hisense TV (Wi-Fi)', 'http://10.81.100.62:5050'),
                _buildPresetChip('📱 Emulator Mode', 'http://10.0.2.2:5050'),
                _buildPresetChip('💻 Laptop Localhost', 'http://localhost:5050'),
                _buildPresetChip('⚡ 127.0.0.1', 'http://127.0.0.1:5050'),
              ],
            ),

            const SizedBox(height: 14),
            if (_statusText.isNotEmpty)
              Text(
                _statusText,
                style: TextStyle(
                  color: _statusColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TVFocusButton(
                  label: 'Auto Detect',
                  isPrimary: false,
                  onTap: () {
                    widget.apiService.checkAndLoad();
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(width: 12),
                TVFocusButton(
                  label: _testing ? 'Connecting...' : 'Connect & Save',
                  isPrimary: true,
                  autoFocus: true,
                  onTap: () => _testAndSave(_controller.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, String url) {
    return ActionChip(
      backgroundColor: TVTheme.surfaceElevated,
      side: const BorderSide(color: TVTheme.border),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      onPressed: () => _testAndSave(url),
    );
  }
}
