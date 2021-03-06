import 'dart:io';
import 'dart:isolate';

import 'package:authpass/utils/path_utils.dart';
import 'package:authpass/utils/platform.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path/path.dart' as path;

final _logger = Logger('logging_utils');

class LoggingUtils {
  factory LoggingUtils() => _instance;

  LoggingUtils._();

  static final _instance = LoggingUtils._();

  AsyncInitializingLogHandler<RotatingFileAppender>? _rotatingFileLoggerCached;
  AsyncInitializingLogHandler<RotatingFileAppender> get _rotatingFileLogger =>
      _rotatingFileLoggerCached ??=
          AsyncInitializingLogHandler<RotatingFileAppender>(builder: () async {
        await PathUtils.waitForRunAppFinished;
        final logsDir = await PathUtils().getLogDirectory();
        final appLogFile = File(path.join(logsDir.path, 'app.log.txt'));
        await appLogFile.parent.create(recursive: true);
        _logger.fine('Logging into $appLogFile');
        return RotatingFileAppender(
          rotateAtSizeBytes: 10 * 1024 * 1024,
          baseFilePath: appLogFile.path,
        );
      });

  List<File> get rotatingFileLoggerFiles =>
      _rotatingFileLogger.delegatedLogHandler?.getAllLogFiles() ?? [];

  void setupLogging({bool fromMainIsolate = false}) {
    Logger.root.level = Level.ALL;
    PrintAppender().attachToLogger(Logger.root);
    if (kIsWeb) {
      return;
    }
    if (fromMainIsolate) {
      _rotatingFileLogger.attachToLogger(Logger.root);
    }
    final isolateDebug =
        '${Isolate.current.debugName} (${Isolate.current.hashCode})'; // NON-NLS
    _logger.info(
        'Running in isolate $isolateDebug ${Isolate.current.debugName} (${Isolate.current.hashCode})');

    Isolate.current.addOnExitListener(RawReceivePort((dynamic val) {
      // ignore: avoid_print
      print('exiting isolate $isolateDebug');
    }).sendPort);

    final exitPort = ReceivePort();
    exitPort.listen((dynamic data) {
      _logger.info(
          'Exiting isolate $isolateDebug ${Isolate.current.debugName} (${Isolate.current.hashCode}');
    }, onDone: () {
      _logger.info('Done $isolateDebug');
    });
    Isolate.current.addOnExitListener(exitPort.sendPort, response: 'exit');
  }

  static Future<Map<String, dynamic>> getDebugDeviceInfo() async {
    final di = DeviceInfoPlugin();
    if (AuthPassPlatform.isWeb) {
      return (await di.webBrowserInfo).importantInfo();
    }
    if (AuthPassPlatform.isAndroid) {
      return (await di.androidInfo).importantInfo();
    }
    if (AuthPassPlatform.isIOS) {
      return (await di.iosInfo).importantInfo();
    }
    if (AuthPassPlatform.isLinux) {
      return (await di.linuxInfo).importantInfo();
    }
    if (AuthPassPlatform.isWindows) {
      return (await di.windowsInfo).importantInfo();
    }
    if (AuthPassPlatform.isMacOS) {
      return (await di.macOsInfo).importantInfo();
    }
    return <String, dynamic>{
      'unknownPlatform': AuthPassPlatform.operatingSystem
    };
  }
}

extension on AndroidDeviceInfo {
  Map<String, dynamic> importantInfo() => <String, dynamic>{
        'board': board,
        'device': device,
        'hardware': hardware,
        'manufacturer': manufacturer,
        'product': product,
        'version': version,
      };
}

extension on IosDeviceInfo {
  Map<String, dynamic> importantInfo() => <String, dynamic>{
        'localizedModel': localizedModel,
        'mode': model,
        'name': name,
      };
}

extension on WebBrowserInfo {
  Map<String, dynamic> importantInfo() => <String, dynamic>{
        'userAgent': userAgent,
      };
}

extension on LinuxDeviceInfo {
  Map<String, dynamic> importantInfo() => <String, dynamic>{
        'name': name,
        'version': version,
      };
}

extension on WindowsDeviceInfo {
  Map<String, dynamic> importantInfo() => <String, dynamic>{
        'systemMemoryInMegabytes': systemMemoryInMegabytes,
      };
}

extension on MacOsDeviceInfo {
  Map<String, dynamic> importantInfo() => <String, dynamic>{
        'arch': arch,
        'model': model,
        'hostName': hostName,
        'osRelease': osRelease,
      };
}

class StringBufferWrapper with ChangeNotifier {
  final StringBuffer _buffer = StringBuffer();

  void writeln(String line) {
    _buffer.writeln(line);
    notifyListeners();
  }

  @override
  String toString() => _buffer.toString();
}

class MemoryAppender extends BaseLogAppender {
  MemoryAppender({this.minLevel = Level.ALL})
      : super(const DefaultLogRecordFormatter());

  final Level minLevel;
  final StringBufferWrapper log = StringBufferWrapper();

  @override
  void handle(LogRecord record) {
    if (record.level.value >= minLevel.value) {
      log.writeln(formatter.format(record));
    }
  }
}
