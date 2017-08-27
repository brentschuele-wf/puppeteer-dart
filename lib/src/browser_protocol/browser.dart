/// The Browser domain defines methods and events for browser managing.

import 'dart:async';
import 'package:meta/meta.dart' show required;
import '../connection.dart';
import 'target.dart' as target;

class BrowserManager {
  final Session _client;

  BrowserManager(this._client);

  /// Get the browser window that contains the devtools target.
  /// [targetId] Devtools agent host id.
  Future<GetWindowForTargetResult> getWindowForTarget(
    target.TargetID targetId,
  ) async {
    Map parameters = {
      'targetId': targetId.toJson(),
    };
    await _client.send('Browser.getWindowForTarget', parameters);
  }

  /// Set position and/or size of the browser window.
  /// [windowId] Browser window id.
  /// [bounds] New window bounds. The 'minimized', 'maximized' and 'fullscreen' states cannot be combined with 'left', 'top', 'width' or 'height'. Leaves unspecified fields unchanged.
  Future setWindowBounds(
    WindowID windowId,
    Bounds bounds,
  ) async {
    Map parameters = {
      'windowId': windowId.toJson(),
      'bounds': bounds.toJson(),
    };
    await _client.send('Browser.setWindowBounds', parameters);
  }

  /// Get position and size of the browser window.
  /// [windowId] Browser window id.
  /// Return: Bounds information of the window. When window state is 'minimized', the restored window position and size are returned.
  Future<Bounds> getWindowBounds(
    WindowID windowId,
  ) async {
    Map parameters = {
      'windowId': windowId.toJson(),
    };
    await _client.send('Browser.getWindowBounds', parameters);
  }
}

class GetWindowForTargetResult {
  /// Browser window id.
  final WindowID windowId;

  /// Bounds information of the window. When window state is 'minimized', the restored window position and size are returned.
  final Bounds bounds;

  GetWindowForTargetResult({
    @required this.windowId,
    @required this.bounds,
  });

  factory GetWindowForTargetResult.fromJson(Map json) {
    return new GetWindowForTargetResult(
      windowId: new WindowID.fromJson(json['windowId']),
      bounds: new Bounds.fromJson(json['bounds']),
    );
  }
}

class WindowID {
  final int value;

  WindowID(this.value);

  factory WindowID.fromJson(int value) => new WindowID(value);

  int toJson() => value;
}

/// The state of the browser window.
class WindowState {
  static const WindowState normal = const WindowState._('normal');
  static const WindowState minimized = const WindowState._('minimized');
  static const WindowState maximized = const WindowState._('maximized');
  static const WindowState fullscreen = const WindowState._('fullscreen');
  static const values = const {
    'normal': normal,
    'minimized': minimized,
    'maximized': maximized,
    'fullscreen': fullscreen,
  };

  final String value;

  const WindowState._(this.value);

  factory WindowState.fromJson(String value) => values[value];

  String toJson() => value;
}

/// Browser window bounds information
class Bounds {
  /// The offset from the left edge of the screen to the window in pixels.
  final int left;

  /// The offset from the top edge of the screen to the window in pixels.
  final int top;

  /// The window width in pixels.
  final int width;

  /// The window height in pixels.
  final int height;

  /// The window state. Default to normal.
  final WindowState windowState;

  Bounds({
    this.left,
    this.top,
    this.width,
    this.height,
    this.windowState,
  });

  factory Bounds.fromJson(Map json) {
    return new Bounds(
      left: json.containsKey('left') ? json['left'] : null,
      top: json.containsKey('top') ? json['top'] : null,
      width: json.containsKey('width') ? json['width'] : null,
      height: json.containsKey('height') ? json['height'] : null,
      windowState: json.containsKey('windowState')
          ? new WindowState.fromJson(json['windowState'])
          : null,
    );
  }

  Map toJson() {
    Map json = {};
    if (left != null) {
      json['left'] = left;
    }
    if (top != null) {
      json['top'] = top;
    }
    if (width != null) {
      json['width'] = width;
    }
    if (height != null) {
      json['height'] = height;
    }
    if (windowState != null) {
      json['windowState'] = windowState.toJson();
    }
    return json;
  }
}