import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Object Detection',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: ObjectDetectionPage(),
    );
  }
}

class ObjectDetectionPage extends StatefulWidget {
  const ObjectDetectionPage({super.key});

  @override
  _ObjectDetectionPageState createState() => _ObjectDetectionPageState();
}

class _ObjectDetectionPageState extends State<ObjectDetectionPage> {
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  Interpreter? _interpreter;
  List<dynamic> _outputLocations = [];
  List<dynamic> _outputClasses = [];
  List<dynamic> _outputScores = [];
  List<String> _labels = [];
  bool _isDetecting = false;
  FlutterTts flutterTts = FlutterTts();
  DateTime _lastSpokenTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadModel();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      final camera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(camera, ResolutionPreset.medium);
      await _cameraController!.initialize();
      setState(() {});

      _cameraController!.startImageStream((cameraImage) {
        if (!_isDetecting && _interpreter != null) {
          _isDetecting = true;
          _runObjectDetection(cameraImage).then((_) {
            _isDetecting = false;
          });
        }
      });
    } catch (e) {
      print("Failed to initialize camera: $e");
    }
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('ssd_mobilenet_v1.tflite');
      print("Model loaded successfully.");

      final labelData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelData.split('\n');
      print("Labels loaded: ${_labels.length}");
    } catch (e) {
      print("Failed to load model or labels: $e");
    }
  }

  Future<void> _speak(String text) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1.0);
    await flutterTts.speak(text);
  }

  Future<void> _runObjectDetection(CameraImage cameraImage) async {
    try {
      final img.Image image = _convertCameraImage(cameraImage);
      final img.Image resizedImage = img.copyResize(
        image,
        width: 300,
        height: 300,
      );
      final input = _convertImageToTensor(resizedImage);

      final outputLocations = List.generate(
        1,
        (_) => List.generate(10, (_) => List.filled(4, 0.0)),
      );
      final outputClasses = List.generate(1, (_) => List.filled(10, 0.0));
      final outputScores = List.generate(1, (_) => List.filled(10, 0.0));
      final numDetections = List.filled(1, 0.0);

      final outputs = {
        0: outputLocations,
        1: outputClasses,
        2: outputScores,
        3: numDetections,
      };

      _interpreter!.runForMultipleInputs([input], outputs);

      setState(() {
        _outputLocations = outputLocations[0];
        _outputClasses = outputClasses[0];
        _outputScores = outputScores[0];
      });

      for (int i = 0; i < _outputScores.length; i++) {
        print('score[$i]: ${_outputScores[i]}');

        if (_outputScores[i] > 0.5) {
          final classIndex = _outputClasses[i].toInt();
          final label =
              classIndex < _labels.length ? _labels[classIndex] : "Unknown";
          print("Detected: $label (score: ${_outputScores[i]})");

          final now = DateTime.now();
          if (now.difference(_lastSpokenTime).inSeconds > 3) {
            await _speak("Detected $label");
            _lastSpokenTime = now;
          }
        }
      }
    } catch (e) {
      print('Object detection failed: $e');
    }
  }

  img.Image _convertCameraImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image convertedImage = img.Image(width: width, height: height);

    final Plane planeY = image.planes[0];
    final Plane planeU = image.planes[1];
    final Plane planeV = image.planes[2];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = (y ~/ 2) * planeU.bytesPerRow + (x ~/ 2);
        final int index = y * width + x;

        final int yp = planeY.bytes[index];
        final int up = planeU.bytes[uvIndex];
        final int vp = planeV.bytes[uvIndex];

        int r = (yp + 1.403 * (vp - 128)).round();
        int g = (yp - 0.344 * (up - 128) - 0.714 * (vp - 128)).round();
        int b = (yp + 1.770 * (up - 128)).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        convertedImage.setPixelRgb(x, y, r, g, b);
      }
    }

    return convertedImage;
  }

  List<List<List<List<double>>>> _convertImageToTensor(img.Image image) {
    List<List<List<List<double>>>> tensor = List.generate(
      1,
      (_) => List.generate(
        300,
        (_) => List.generate(300, (_) => List.filled(3, 0.0)),
      ),
    );

    for (int y = 0; y < 300; y++) {
      for (int x = 0; x < 300; x++) {
        final pixel = image.getPixelSafe(x, y);
        tensor[0][y][x][0] = pixel.r / 255.0;
        tensor[0][y][x][1] = pixel.g / 255.0;
        tensor[0][y][x][2] = pixel.b / 255.0;
      }
    }

    return tensor;
  }

  Widget _buildObjectDetectionCanvas() {
    return Stack(
      children: [
        if (_cameraController != null && _cameraController!.value.isInitialized)
          CameraPreview(_cameraController!),
        for (int i = 0; i < _outputLocations.length; i++)
          if (_outputScores[i] > 0.5)
            Positioned(
              left: _outputLocations[i][1] * MediaQuery.of(context).size.width,
              top: _outputLocations[i][0] * MediaQuery.of(context).size.height,
              width:
                  (_outputLocations[i][3] - _outputLocations[i][1]) *
                  MediaQuery.of(context).size.width,
              height:
                  (_outputLocations[i][2] - _outputLocations[i][0]) *
                  MediaQuery.of(context).size.height,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      'Class: ${_labels[_outputClasses[i].toInt()]}',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    Text(
                      'Score: ${(_outputScores[i] * 100).toStringAsFixed(1)}%',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Object Detection')),
      body: Center(
        child:
            (_cameraController != null &&
                    _cameraController!.value.isInitialized)
                ? _buildObjectDetectionCanvas()
                : CircularProgressIndicator(),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    flutterTts.stop();
    super.dispose();
  }
}
