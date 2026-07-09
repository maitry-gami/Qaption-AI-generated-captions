import sys

def modify_main_dart():
    file_path = "lib/main.dart"
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except FileNotFoundError:
        print("lib/main.dart not found.")
        return

    # Add _templates
    for i, line in enumerate(lines):
        if "class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {" in line:
            lines.insert(i + 1, "  final List<Map<String, String>> _templates = [{'id': 'hormozi-style', 'name': 'Hormozi Style'},{'id': 'ali-abdaal', 'name': 'Ali Abdaal'},{'id': 'mr-beast', 'name': 'Mr. Beast'},{'id': 'karaoke-flow', 'name': 'Karaoke Flow'},{'id': 'pulse-wave', 'name': 'Pulse Wave'},{'id': 'typewriter-pro', 'name': 'Typewriter Pro'},{'id': 'neon-glow', 'name': 'Neon Glow'},{'id': 'impact-bounce', 'name': 'Impact Bounce'},{'id': 'minimalist-bg', 'name': 'Minimalist Overlay'}];\n")
            break

    # Comment out _startCaptionPipeline in _pickVideo
    for i, line in enumerate(lines):
        if "_startCaptionPipeline();" in line and "Auto-start" not in lines[i-1]:
            # Verify if we are inside _pickVideo by checking previous lines loosely
            for j in range(i, max(0, i - 30), -1):
                if "Future<void> _pickVideo() async {" in lines[j]:
                    lines[i] = "      // _startCaptionPipeline();\n"
                    break

    # Replace _startCaptionPipeline in _initServerAndWebView or initState
    in_init_server = False
    for i, line in enumerate(lines):
        if "if (widget.project!.captionResult != null) {" in line:
            in_init_server = True
        if in_init_server and "_startCaptionPipeline();" in line:
            lines[i] = "            setState(() { _pipelineStatus = CaptionPipelineStatus.videoSelected; });\n"
            in_init_server = False

    # Insert _buildStyleSelectionOverlay before _buildTranscribingOverlay
    overlay_func = """
  Widget _buildStyleSelectionOverlay() {
    return Container(
      color: const Color(0xFF151517),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Text(
                'Choose Your Style',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _templates.length,
                  itemBuilder: (context, index) {
                    final t = _templates[index];
                    return GestureDetector(
                      onTap: () {
                        _setStyle(t['id']!);
                        _startCaptionPipeline();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF222225),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              'assets/gifs/${t['id']}.gif',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.black26,
                                child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                              ),
                            ),
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                color: Colors.black54,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  t['name']!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

"""
    for i, line in enumerate(lines):
        if "Widget _buildTranscribingOverlay() {" in line:
            lines.insert(i, overlay_func)
            break

    # Add to build() method
    for i, line in enumerate(lines):
        if "_buildTranscribingOverlay()," in line:
            lines.insert(i, "          if (_pipelineStatus == CaptionPipelineStatus.videoSelected) _buildStyleSelectionOverlay(),\n")
            break

    with open(file_path, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print("Modifications applied.")

modify_main_dart()
