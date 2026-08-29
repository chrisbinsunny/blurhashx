import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:blurhashx/blurhashx.dart';

void main() {
  runApp(const BlurHashExampleApp());
}

class BlurHashExampleApp extends StatelessWidget {
  const BlurHashExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlurHashX Playground',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
      ),
      home: const BlurHashHomePage(),
    );
  }
}

class BlurHashHomePage extends StatefulWidget {
  const BlurHashHomePage({super.key});

  @override
  State<BlurHashHomePage> createState() => _BlurHashHomePageState();
}

class _BlurHashHomePageState extends State<BlurHashHomePage> {
  final TextEditingController _hashController = TextEditingController();
  final TextEditingController _urlController = TextEditingController(
    text: 'https://flutter.dev/assets/1N5Jz1tLlbGEC9sU49O97IA.546ed0164505ded48eb63a2d6165dadb.webp',
  );

  final ImagePicker _picker = ImagePicker();

  ui.Image? _decodedBlurHashImage;
  Uint8List? _rawOriginalImageBytes;
  Color? _averageColor;
  String _componentInfo = '...';
  double _punch = 1.0;
  bool _isProcessing = false;
  bool _showOriginalImage = false;
  String? _benchmarkText;

  @override
  void initState() {
    super.initState();
    // Automatically load, encode, and decode the default WebP image on launch
    _downloadAndEncodeUrl();
  }

  @override
  void dispose() {
    _hashController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  /// Processes and decodes a BlurHash string into an Image
  Future<void> _processHash(String hash) async {
    setState(() => _isProcessing = true);

    final isValid = BlurHash.isValid(hash);
    if (!isValid) {
      setState(() {
        _decodedBlurHashImage = null;
        _averageColor = null;
        _componentInfo = 'Invalid';
        _isProcessing = false;
      });
      return;
    }

    try {
      // 1. O(1) Instant Average Color Extraction
      final avg = BlurHash.decodeAverageColor(hash);
      final avgColor = Color.fromARGB(255, avg.r, avg.g, avg.b);

      // 2. Component Inspection
      final comps = BlurHash.components(hash);
      final compInfo = '${comps.componentX} × ${comps.componentY} (${hash.length} chars)';

      // 3. Fast RGBA Decoding
      const int targetWidth = 64;
      const int targetHeight = 64;
      final Uint8List pixels = BlurHash.decode(
        hash,
        width: targetWidth,
        height: targetHeight,
        punch: _punch,
      );

      // Convert raw RGBA buffer to a native ui.Image for rendering
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
      final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: targetWidth,
        height: targetHeight,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frame = await codec.getNextFrame();

      setState(() {
        _averageColor = avgColor;
        _componentInfo = compInfo;
        _decodedBlurHashImage = frame.image;
        _isProcessing = false;
      });
    } catch (_) {
      setState(() => _isProcessing = false);
    }
  }

  /// Pick an image from gallery or camera, hardware-encode to BlurHash
  Future<void> _pickAndEncodeImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null) return;

      setState(() => _isProcessing = true);
      final Uint8List bytes = await file.readAsBytes();

      // Measure BlurHashX hardware-accelerated encoding speed
      final sw = Stopwatch()..start();
      final hash = await BlurHash.encodeImageBytes(bytes);
      sw.stop();

      setState(() {
        _rawOriginalImageBytes = bytes;
        _hashController.text = hash;
        _showOriginalImage = false;
        _benchmarkText = '⚡ Encoded in ${sw.elapsedMilliseconds}ms (${bytes.lengthInBytes ~/ 1024} KB)';
      });

      await _processHash(hash);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to encode image: $e')),
        );
      }
      setState(() => _isProcessing = false);
    }
  }

  /// Download an image from URL and hardware-encode to BlurHash
  Future<void> _downloadAndEncodeUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid HTTP/HTTPS URL')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Server returned status ${response.statusCode}');
      }

      final Uint8List bytes = response.bodyBytes;

      // Measure BlurHashX hardware-accelerated encoding speed
      final sw = Stopwatch()..start();
      final hash = await BlurHash.encodeImageBytes(bytes);
      sw.stop();

      setState(() {
        _rawOriginalImageBytes = bytes;
        _hashController.text = hash;
        _showOriginalImage = false;
        _benchmarkText = '⚡ Encoded in ${sw.elapsedMilliseconds}ms (${bytes.lengthInBytes ~/ 1024} KB)';
      });

      await _processHash(hash);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download/encode failed: $e')),
        );
      }
      setState(() => _isProcessing = false);
    }
  }

  /// Copy current hash to clipboard
  void _copyHashToClipboard() {
    final text = _hashController.text.trim();
    if (text.isEmpty) return;

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Copied "$text" to clipboard!')),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasOriginal = _rawOriginalImageBytes != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt, color: Colors.amberAccent),
            SizedBox(width: 6),
            Text(
              'BlurHashX Playground',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Interactive Preview Card (Tap to toggle Original <-> BlurHash)
            GestureDetector(
              onTap: hasOriginal
                  ? () => setState(() => _showOriginalImage = !_showOriginalImage)
                  : null,
              child: Card(
                elevation: 6,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _averageColor?.withValues(alpha: 0.3) ?? Colors.white10,
                    width: 1.5,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        color: const Color(0xFF0F172A),
                        child: _isProcessing
                            ? const Center(
                                child: CircularProgressIndicator(),
                              )
                            : AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                layoutBuilder: (currentChild, previousChildren) {
                                  return Stack(
                                    fit: StackFit.expand,
                                    children: <Widget>[
                                      ...previousChildren,
                                      if (currentChild != null) currentChild,
                                    ],
                                  );
                                },
                                child: _showOriginalImage && hasOriginal
                                    ? Image.memory(
                                        _rawOriginalImageBytes!,
                                        key: const ValueKey('original_image'),
                                        fit: BoxFit.cover,
                                      )
                                    : _decodedBlurHashImage != null
                                        ? RawImage(
                                            key: const ValueKey('blurhash_image'),
                                            image: _decodedBlurHashImage,
                                            fit: BoxFit.cover,
                                            filterQuality: FilterQuality.medium,
                                          )
                                        : Container(
                                            key: const ValueKey('invalid_blurhash'),
                                            color: Colors.grey.shade900,
                                            child: const Center(
                                              child: Text(
                                                'Invalid BlurHash',
                                                style: TextStyle(color: Colors.redAccent),
                                              ),
                                            ),
                                          ),
                              ),
                      ),
                    ),

                    // Tap toggle badge
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _showOriginalImage ? Icons.blur_on : Icons.image,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              hasOriginal
                                  ? (_showOriginalImage
                                      ? 'Viewing Original (Tap for BlurHash)'
                                      : 'Viewing BlurHash (Tap for Original)')
                                  : 'BlurHash Preview',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Speed benchmark banner
                    if (_benchmarkText != null)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            _benchmarkText!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Metadata Info HUD (Clean, read-only inspection display)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  // Components Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'COMPONENTS',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _componentInfo,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),

                  // Subtle Divider
                  Container(
                    width: 1,
                    height: 28,
                    color: Colors.white12,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                  ),

                  // Dominant Average Color Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'DOMINANT COLOR',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: _averageColor ?? Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white30, width: 1),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _averageColor != null
                                  ? '#${_averageColor!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}'
                                  : 'N/A',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // BlurHash Input Field with Copy button
            TextField(
              controller: _hashController,
              decoration: InputDecoration(
                labelText: 'Active BlurHash',
                hintText: 'Enter a valid BlurHash...',
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                prefixIcon: const Icon(Icons.tag, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copy Hash',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: _copyHashToClipboard,
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () => _processHash(_hashController.text),
                    ),
                  ],
                ),
              ),
              onChanged: (value) => _processHash(value.trim()),
            ),
            const SizedBox(height: 14),

            // Contrast (Punch) Slider
            Row(
              children: [
                const Text(
                  'Contrast (Punch):',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                Expanded(
                  child: Slider(
                    value: _punch,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: _punch.toStringAsFixed(1),
                    onChanged: (v) {
                      setState(() => _punch = v);
                      _processHash(_hashController.text);
                    },
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 28),

            // Section: Local Image -> Hash
            const Text(
              'Encode Local Image',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: const Text('Pick Gallery Image'),
                    onPressed: () => _pickAndEncodeImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Take Photo'),
                    onPressed: () => _pickAndEncodeImage(ImageSource.camera),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Section: URL -> Hash
            const Text(
              'Encode from Image URL',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: 'https://example.com/photo.jpg',
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _downloadAndEncodeUrl,
                  child: const Text('Encode URL'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
