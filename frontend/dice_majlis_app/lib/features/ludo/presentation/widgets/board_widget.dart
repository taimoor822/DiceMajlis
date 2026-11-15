import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BoardWidget extends StatefulWidget {
  final String assetPath;

  const BoardWidget({
    super.key,
    this.assetPath = 'assets/board/majlis_board.svg',
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget> {
  Future<String>? _svgFuture;
  AssetBundle? _bundle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextBundle = DefaultAssetBundle.of(context);
    if (_svgFuture == null || _bundle != nextBundle) {
      _bundle = nextBundle;
      _svgFuture = nextBundle.loadString(widget.assetPath);
    }
  }

  @override
  void didUpdateWidget(covariant BoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      final bundle = _bundle ?? DefaultAssetBundle.of(context);
      _bundle = bundle;
      _svgFuture = bundle.loadString(widget.assetPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FutureBuilder<String>(
        future: _svgFuture,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return SvgPicture.string(
              snapshot.data!,
              fit: BoxFit.fill,
              alignment: Alignment.center,
            );
          }

          if (snapshot.hasError) {
            return const ColoredBox(
              color: Color(0xFF12172A),
              child: Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 36,
                  color: Colors.white70,
                ),
              ),
            );
          }

          return const ColoredBox(
            color: Color(0xFF12172A),
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          );
        },
      ),
    );
  }
}
