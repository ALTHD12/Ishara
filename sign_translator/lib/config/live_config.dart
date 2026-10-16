/// Client-side live-pipeline tuning, in one place.
/// Server-side counterparts: backend/live_config.py.
class LiveConfig {
  /// Max frames/s sent while translating. The server resamples frames onto a
  /// 30 fps grid by timestamp, so any rate works; higher = slightly faster
  /// decisions, more laptop CPU and Wi-Fi load.
  static const double maxSendFps = 12;

  /// Max frames/s while recording training data. 0 = uncapped (only limited by
  /// backpressure), which is how the existing training data was recorded.
  static const double recordingMaxSendFps = 0;

  /// Backpressure: next frame is sent when the previous result arrives, or
  /// after this long if it never does (lost frame, server hiccup).
  static const Duration resultTimeout = Duration(milliseconds: 800);

  /// Words are appended when the server reports a new decision event (its
  /// majority vote + repeat cooldown already did the smoothing). Set >1 to
  /// additionally require N consecutive results showing the same sign
  /// (legacy behaviour was 2 + "never the same word twice in a row").
  static const int clientConsecutiveThreshold = 1;
}
