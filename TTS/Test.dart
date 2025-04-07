import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TTSExample(),
    );
  }
}

class TTSExample extends StatefulWidget {
  @override
  _TTSExampleState createState() => _TTSExampleState();
}

class _TTSExampleState extends State<TTSExample> {
  FlutterTts flutterTts = FlutterTts();

  Future<void> _speak(String text) async {
    await flutterTts.setLanguage("ko-KR");//언어 설정
    await flutterTts.setSpeechRate(2); // 말하기 속도 설정
    await flutterTts.speak(text);
  }

  @override//구현부부
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('TTS Example'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _speak("전방에 사물이 존재합니다"),//Speak 눌렸을때 작동
          child: Text('Speak'),
        ),
      ),
    );
  }
}
