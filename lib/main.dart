import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
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
  @override
  _ObjectDetectionPageState createState() => _ObjectDetectionPageState();
}

class _ObjectDetectionPageState extends State<ObjectDetectionPage> {
  late CameraController _cameraController;
  late List<CameraDescription> _cameras;
  Interpreter? _interpreter;
  List<dynamic> _outputLocations = [];
  List<dynamic> _outputClasses = [];
  List<dynamic> _outputScores = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadModel();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw CameraException("No available cameras", "No cameras found");
      }

      final camera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(camera, ResolutionPreset.high);
      await _cameraController.initialize();
      setState(() {});

      _cameraController.startImageStream((cameraImage) {
        if (_interpreter != null) {
          _runObjectDetection(cameraImage);
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
    } catch (e) {
      print("Failed to load model: $e");
    }
  }

  Future<void> _runObjectDetection(CameraImage cameraImage) async {
    if (_interpreter == null) {
      print("Interpreter is not initialized yet.");
      return;
    }

    try {
      // 카메라 이미지를 리사이즈하고 RGB 형식으로 변환
      final img.Image image = _cameraImageToImage(cameraImage);
      final img.Image resizedImage = img.copyResize(
        image,
        width: 300,
        height: 300,
      );
      final input = _convertImageToTensor(resizedImage);

      final outputLocations = List.generate(
        10,
        (_) => List.generate(4, (_) => 0.0),
      );
      final outputClasses = List.generate(10, (_) => 0.0);
      final outputScores = List.generate(10, (_) => 0.0);

      final output = {
        'locations': outputLocations,
        'classes': outputClasses,
        'scores': outputScores,
      };

      _interpreter!.run(input, output);

      setState(() {
        _outputLocations = outputLocations;
        _outputClasses = outputClasses;
        _outputScores = outputScores;
      });

      // 객체 감지된 항목 출력
      for (int i = 0; i < _outputClasses.length; i++) {
        if (_outputScores[i] > 0.1) {
          // 신뢰도 기준을 0.2로 낮춤
          print(
            "Detected object ${_outputClasses[i]} with score: ${_outputScores[i]}",
          );
        }
      }
    } catch (e) {
      print('Object detection failed: $e');
    }
  }

  img.Image _cameraImageToImage(CameraImage cameraImage) {
    final plane = cameraImage.planes.first;
    final bytes = plane.bytes;
    final image = img.decodeImage(Uint8List.fromList(bytes));
    return image!;
  }

  List<List<List<List<double>>>> _convertImageToTensor(img.Image image) {
    final height = image.height;
    final width = image.width;

    List<List<List<List<double>>>> tensor = List.generate(
      1,
      (_) => List.generate(
        height,
        (_) => List.generate(width, (_) => List.generate(3, (_) => 0.0)),
      ),
    );

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r / 255.0;
        final g = pixel.g / 255.0;
        final b = pixel.b / 255.0;
        tensor[0][y][x] = [r, g, b];
      }
    }

    return tensor;
  }

  Widget _buildObjectDetectionCanvas() {
    return Stack(
      children: [
        CameraPreview(_cameraController),
        for (int i = 0; i < _outputLocations.length; i++)
          Positioned(
            left: _outputLocations[i][0] * MediaQuery.of(context).size.width,
            top: _outputLocations[i][1] * MediaQuery.of(context).size.height,
            child: Container(
              width: _outputLocations[i][2] * MediaQuery.of(context).size.width,
              height:
                  _outputLocations[i][3] * MediaQuery.of(context).size.height,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red, width: 2),
                color: Colors.transparent,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    'Class: ${_outputClasses[i]}',
                    style: TextStyle(color: Colors.red, fontSize: 16),
                  ),
                  Text(
                    'Score: ${_outputScores[i].toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.red, fontSize: 16),
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
            _cameraController.value.isInitialized
                ? _buildObjectDetectionCanvas()
                : Center(child: CircularProgressIndicator()),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }
}
