import 'dart:typed_data';

class CameraUtils {
  static Map<String, dynamic>? yuvConverter(Map<String, dynamic> data) {
    try {
      final formatName = data['formatName'] as String;
      final width = data['width'] as int;
      final height = data['height'] as int;
      final planesList = data['planes'] as List<dynamic>;
      
      // Calculate downsample step to guarantee ~300px max dimension for ultra-fast processing
      final step = (width > height ? width : height) ~/ 300;
      final sampleStep = step > 0 ? step : 1;
      
      final outWidth = width ~/ sampleStep;
      final outHeight = height ~/ sampleStep;
      
      if (formatName == 'bgra8888') {
        final bgra = planesList[0] as Uint8List;
        final rgb = Uint8List(outWidth * outHeight * 3);
        int pixelIndex = 0;
        for (int y = 0; y < outHeight; y++) {
          for (int x = 0; x < outWidth; x++) {
            final srcY = y * sampleStep;
            final srcX = x * sampleStep;
            final i = (srcY * width + srcX) * 4;
            if (i + 2 < bgra.length) {
              rgb[pixelIndex++] = bgra[i + 2]; // R
              rgb[pixelIndex++] = bgra[i + 1]; // G
              rgb[pixelIndex++] = bgra[i];     // B
            }
          }
        }
        return {'width': outWidth, 'height': outHeight, 'bytes': rgb};
      }

      final yPlane = planesList[0] as Uint8List;
      final uPlane = planesList[1] as Uint8List;
      final vPlane = planesList[2] as Uint8List;
      final yRowStride = data['yRowStride'] as int;
      final uvRowStride = data['uvRowStride'] as int;
      final uvPixelStride = data['uvPixelStride'] as int;
      
      final rgb = Uint8List(outWidth * outHeight * 3);

      int pixelIndex = 0;
      for (int y = 0; y < outHeight; y++) {
        for (int x = 0; x < outWidth; x++) {
          final srcY = y * sampleStep;
          final srcX = x * sampleStep;
          
          final yIndex = srcY * yRowStride + srcX;
          final uvIndex = (srcY ~/ 2) * uvRowStride + (srcX ~/ 2) * uvPixelStride;
          
          final yVal = yPlane[yIndex];
          final uVal = uPlane[uvIndex] - 128;
          final vVal = vPlane[uvIndex] - 128;

          final r = yVal + ((1436 * vVal) >> 10);
          final g = yVal - ((352 * uVal + 731 * vVal) >> 10);
          final b = yVal + ((1814 * uVal) >> 10);

          rgb[pixelIndex++] = r < 0 ? 0 : (r > 255 ? 255 : r);
          rgb[pixelIndex++] = g < 0 ? 0 : (g > 255 ? 255 : g);
          rgb[pixelIndex++] = b < 0 ? 0 : (b > 255 ? 255 : b);
        }
      }
      return {'width': outWidth, 'height': outHeight, 'bytes': rgb};
    } catch (e) {
      return null;
    }
  }
}
