# tflite_flutter (currently unused by lib/) references the optional GPU delegate;
# without this, R8 fails release builds with "Missing class GpuDelegateFactory$Options".
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options
