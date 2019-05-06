import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:chrome_dev_tools/target.dart';
import 'package:chrome_dev_tools/chrome_dev_tools.dart';

export 'package:chrome_dev_tools/chrome_dev_tools.dart' show Client;

class Connection implements Client {
  final Logger _logger = Logger('connection');
  static int _lastId = 0;
  final WebSocket _webSocket;
  final String url;
  final Map<int, _Message> _messagesInFly = {};
  final Map<String, Session> sessions = {};
  final StreamController<Event> _eventController =
      StreamController<Event>.broadcast(sync: true);
  TargetApi _targetApi;
  final List<StreamSubscription> _subscriptions = [];

  Connection._(this._webSocket, this.url) {
    _subscriptions.add(_webSocket.listen(_onMessage, onError: (error) {
      print('Websocket error: $error');
    }));

    _targetApi = TargetApi(this);

    _webSocket.done.then((_) => dispose(
        'Websocket.done(code: ${_webSocket.closeCode}, reason: ${_webSocket.closeReason})'));
  }

  TargetApi get targetApi => _targetApi;

  static Future<Connection> create(String url) async {
    WebSocket webSocket = await WebSocket.connect(url);

    return Connection._(webSocket, url);
  }

  @override
  Stream<Event> get onEvent => _eventController.stream;

  @override
  Future<Map> send(String method, [Map parameters]) {
    var id = _rawSend(method, parameters);
    var message = _Message(method);
    _messagesInFly[id] = message;

    return message.completer.future;
  }

  int _rawSend(String method, Map parameters, {SessionID sessionId}) {
    int id = ++_lastId;
    String message =
        _encodeMessage(id, method, parameters, sessionId: sessionId);

    _logger.fine('SEND ► $message');
    _webSocket.add(message);

    return id;
  }

  Future<Session> createSession(TargetInfo targetInfo) async {
    SessionID sessionId =
        await _targetApi.attachToTarget(targetInfo.targetId, flatten: true);

    Session session = sessions[sessionId.value];
    assert(session != null);
    return session;
  }

  _onMessage(messageArg) {
    String message = messageArg;
    Map object = jsonDecode(message);
    int id = object['id'];
    String method = object['method'];
    String sessionId = object['sessionId'];
    if (method == 'Target.attachedToTarget') {
      Map params = object['params'];
      String sessionId = params['sessionId'];
      var session = Session(this, SessionID(sessionId));
      sessions[sessionId] = session;
    } else if (method == 'Target.detachedFromTarget') {
      Map params = object['params'];
      String sessionId = params['sessionId'];
      var session = sessions[sessionId];
      if (session != null) {
        session.dispose(reason: 'Target.detachedFromTarget');
        sessions.remove(sessionId);
      }
    } else if (sessionId != null) {
      var session = sessions[sessionId];
      if (session != null) {
        _logger.fine('◀ RECV $message');

        session._onMessage(object);
      }
    } else if (id != null) {
      _logger.fine('◀ RECV $id $message');

      _Message messageInFly = _messagesInFly.remove(id);
      assert(messageInFly != null);

      Map error = object['error'];
      if (error != null) {
        messageInFly.completer.completeError(ServerException(error['message']));
      } else {
        messageInFly.completer.complete(object['result']);
      }
    } else {
      String method = object['method'];
      Map params = object['params'];

      _logger.fine('◀ EVENT $message');

      _eventController.add(Event(method, params));
    }
  }

  void dispose(String reason) {
    _eventController.close();
    for (var message in _messagesInFly.values) {
      message.completer
          .completeError(TargetClosedException(message.method, reason: reason));
    }
    _messagesInFly.clear();

    for (Session session in sessions.values) {
      session.dispose(reason: 'Connection.dispose(reason: $reason)');
    }
    sessions.clear();

    for (StreamSubscription subscription in _subscriptions) {
      subscription.cancel();
    }

    _webSocket.close(WebSocketStatus.normalClosure, 'Connection.dispose');
  }

  Future get disconnected => _webSocket.done;
}

String _encodeMessage(int id, String method, Map<String, dynamic> parameters,
    {SessionID sessionId}) {
  var message = {
    'id': id,
    'method': method,
    'params': parameters,
  };
  if (sessionId != null) {
    message['sessionId'] = sessionId.value;
  }
  return jsonEncode(message);
}

class Session implements Client {
  final SessionID sessionId;
  final Connection connection;
  final _messagesInFly = <int, _Message>{};
  final _eventController = StreamController<Event>.broadcast(sync: true);
  final _onClose = Completer<void>();

  Session(this.connection, this.sessionId);

  @override
  Future<Map> send(String method, [Map parameters]) {
    if (_eventController.isClosed) {
      throw Exception('Session closed');
    }
    int id = connection._rawSend(method, parameters, sessionId: sessionId);

    var message = _Message(method);
    _messagesInFly[id] = message;

    return message.completer.future;
  }

  @override
  Stream<Event> get onEvent => _eventController.stream;

  Future<void> get closed => _onClose.future;

  _onMessage(Map object) {
    int id = object['id'];
    if (id != null) {
      var message = _messagesInFly.remove(id);
      Map error = object['error'];
      if (error != null) {
        message.completer.completeError(ServerException(error['message']));
      } else {
        message.completer.complete(object['result']);
      }
    } else {
      _eventController.add(Event(object['method'], object['params']));
    }
  }

  bool get isClosed => _onClose.isCompleted;

  Future<void> detach() async {
    await connection.targetApi.detachFromTarget(sessionId: sessionId);
  }

  void dispose({@required String reason}) {
    if (_eventController.isClosed) return;

    _eventController.close();
    for (var message in _messagesInFly.values) {
      message.completer
          .completeError(TargetClosedException(message.method, reason: reason));
    }
    _messagesInFly.clear();
    _onClose.complete();
  }
}

class ServerException implements Exception {
  final String message;

  ServerException(this.message);

  @override
  toString() => message;

  static matcher(String message) =>
      (e) => e is ServerException && e.message == message;
}

class _Message {
  final completer = Completer<Map>();
  final String method;

  _Message(this.method);
}

class TargetClosedException implements Exception {
  final String method;
  final String reason;

  TargetClosedException(this.method, {@required this.reason});

  @override
  String toString() =>
      'TargetClosedException(method: $method, reason: $reason)';
}