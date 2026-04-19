class ConversionResult {
  final String inputPath;
  final String outputPath;
  final int inputSize;
  final int outputSize;
  final bool success;
  final String? error;

  ConversionResult({
    required this.inputPath,
    required this.outputPath,
    required this.inputSize,
    required this.outputSize,
    required this.success,
    this.error,
  });

  int get savedBytes => inputSize - outputSize;
}
