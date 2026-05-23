import 'dart:math' as math;

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';

import 'package:tflite_flutter/tflite_flutter.dart';



class Classifier {

  static const String _modelFile = 'action.tflite';

  static const String _labelFile = 'labels.txt';

  static const int _sequenceLength = 30;

  static const int _inputSize = 201;



  Interpreter? _interpreter;

  List<String> _labels = [];

  bool _isLoaded = false;

  String? _loadError;



  bool get isLoaded => _isLoaded;

  String? get loadError => _loadError;

  int get labelCount => _labels.length;

  List<double> _calibratedProbabilities(List<double> raw) {

    if (raw.isEmpty) return raw;

    final sum = raw.fold<double>(0, (a, b) => a + b);

    final looksLikeProbabilities = sum > 0.98 &&

        sum < 1.02 &&

        raw.every((x) => x >= 0 && x <= 1.0);

    if (looksLikeProbabilities) {

      return sum == 1.0 ? raw : raw.map((x) => x / sum).toList();

    }

    double maxLogit = raw[0];

    for (final v in raw.skip(1)) {

      if (v > maxLogit) maxLogit = v;

    }

    double expSum = 0;

    final exps = List<double>.generate(raw.length, (i) {

      final e = math.exp(raw[i] - maxLogit);

      expSum += e;

      return e;

    });

    return exps.map((e) => e / expSum).toList();

  }



  Future<void> loadModel() async {

    _isLoaded = false;

    _loadError = null;

    _interpreter?.close();

    _interpreter = null;



    try {

      debugPrint("Loading labels...");

      final labelData = await rootBundle.loadString('assets/$_labelFile');

      _labels = labelData

          .split('\n')

          .map((s) => s.trim())

          .where((s) => s.isNotEmpty)

          .toList();

      debugPrint("Labels: ${_labels.length}");



      final options = InterpreterOptions()..threads = 2;

      Object? lastError;



      // 1) fromAsset — วิธีมาตรฐนบน Flutter

      try {

        debugPrint("Loading TFLite from asset...");

        _interpreter = await Interpreter.fromAsset(

          'assets/$_modelFile',

          options: options,

        );

      } catch (e) {

        lastError = e;

        debugPrint("fromAsset failed: $e");

      }



      // 2) fromBuffer — สำรอง

      if (_interpreter == null) {

        try {

          debugPrint("Loading TFLite from buffer...");

          final modelData = await rootBundle.load('assets/$_modelFile');

          _interpreter = Interpreter.fromBuffer(

            modelData.buffer.asUint8List(),

            options: options,

          );

        } catch (e) {

          lastError = e;

          debugPrint("fromBuffer failed: $e");

        }

      }



      if (_interpreter == null) {

        throw lastError ??

            'Unable to create interpreter (โมเดลอาจมี op ที่มือถือไม่รองรับ — รัน export_tflite.py ใหม่)';

      }



      final inputShape = _interpreter!.getInputTensor(0).shape;

      final outputShape = _interpreter!.getOutputTensor(0).shape;

      debugPrint("Model input: $inputShape, output: $outputShape");



      _isLoaded = true;

      debugPrint("loadModel OK");

    } catch (e, st) {

      _loadError = e.toString();

      debugPrint("loadModel failed: $e\n$st");

    }

  }



  Map<String, dynamic>? predict(List<List<double>> buffer) {

    if (!_isLoaded || _interpreter == null) return null;



    if (buffer.length != _sequenceLength) {

      debugPrint("Buffer length ${buffer.length}, need $_sequenceLength");

      return null;

    }



    if (buffer.any((frame) => frame.length != _inputSize)) {

      debugPrint("Invalid keypoint size");

      return null;

    }



    try {

      final input = [

        List.generate(_sequenceLength, (f) {

          return Float32List.fromList(buffer[f]);

        }),

      ];



      final outShape = _interpreter!.getOutputTensor(0).shape;

      final outFlat = outShape.fold<int>(1, (a, b) => a * b);

      final output = List<double>.filled(outFlat, 0.0).reshape(outShape);



      _interpreter!.run(input, output);



      final raw = List<double>.from(output[0]);

      final probs = _calibratedProbabilities(raw);

      if (probs.isEmpty) return null;



      int maxIndex = 0;

      for (int i = 1; i < probs.length; i++) {

        if (probs[i] > probs[maxIndex]) maxIndex = i;

      }



      int secondIndex = maxIndex;

      double secondProb = -1.0;

      for (int i = 0; i < probs.length; i++) {

        if (i == maxIndex) continue;

        if (secondProb < 0 || probs[i] > secondProb) {

          secondProb = probs[i];

          secondIndex = i;

        }

      }



      final maxScore = probs[maxIndex];

      final secondScore =

          probs.length > 1 ? (secondIndex == maxIndex ? 0.0 : secondProb) : 0.0;



      final label = (maxIndex >= 0 && maxIndex < _labels.length)

          ? _labels[maxIndex]

          : "Unknown";



      final topK = _buildTopK(probs, 3);

      return {

        "label": label,

        "confidence": maxScore,

        "index": maxIndex,

        "second_confidence": secondScore,

        "second_index": secondIndex,

        "margin": maxScore - secondScore,

        "top_k": topK,

        "probabilities": probs,

      };

    } catch (e) {

      debugPrint("Predict error: $e");

      return null;

    }

  }

  List<Map<String, dynamic>> _buildTopK(List<double> probs, int k) {

    final indices = List.generate(probs.length, (i) => i)

      ..sort((a, b) => probs[b].compareTo(probs[a]));

    final take = math.min(k, indices.length);

    return List.generate(take, (rank) {

      final i = indices[rank];

      return {

        "label": i < _labels.length ? _labels[i] : "?",

        "confidence": probs[i],

        "index": i,

      };

    });

  }

  void close() {

    _interpreter?.close();

    _interpreter = null;

    _isLoaded = false;

  }

}


