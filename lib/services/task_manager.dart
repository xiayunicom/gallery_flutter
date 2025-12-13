// lib/services/task_manager.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import '../config.dart'; // 引入配置

class TaskManager {
  static final TaskManager _instance = TaskManager._internal();
  factory TaskManager() => _instance;
  TaskManager._internal();

  final ValueNotifier<Map<String, dynamic>> tasksNotifier = ValueNotifier({});
  final StreamController<String> _refreshEventController = StreamController.broadcast();
  Stream<String> get refreshStream => _refreshEventController.stream;

  final Map<String, int> _fileVersions = {};

  void init() {
    print("Initializing Global SSE Connection...");
    try {
      SSEClient.subscribeToSSE(
        method: SSERequestType.GET,
        url: '$serverUrl/api/events',
        header: {},
      ).listen((event) {
        if (event.data != null && event.data!.isNotEmpty) {
          try {
            final data = jsonDecode(event.data!);
            final taskId = data['taskId'];
            final type = data['type'];

            final currentTasks = Map<String, dynamic>.from(tasksNotifier.value);

            bool isActuallyDone = type == 'done';
            if (!isActuallyDone && data['current'] != null && data['total'] != null) {
              if (data['current'] >= data['total'] && data['total'] > 0) {
                isActuallyDone = true;
                data['type'] = 'done';
              }
            }

            if (isActuallyDone) {
              if (data['message'].toString().contains('Rotat') ||
                  data['message'].toString().contains('Convert')) {
                _refreshEventController.add('refresh');
              }
            }

            currentTasks[taskId] = data;
            tasksNotifier.value = currentTasks;
          } catch (e) {
            print("SSE Parse Error: $e");
          }
        }
      });
    } catch (e) {
      print("SSE Connection Error: $e");
    }
  }

  String getImgUrl(String path) {
    final encodedPath = Uri.encodeComponent(path);
    final version = _fileVersions[path] ?? 0;
    return "$serverUrl/file/$encodedPath?v=$version";
  }

  void bumpVersions(List<String> paths) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var path in paths) {
      _fileVersions[path] = now;
    }
  }

  void removeTask(String taskId) {
    final currentTasks = Map<String, dynamic>.from(tasksNotifier.value);
    currentTasks.remove(taskId);
    tasksNotifier.value = currentTasks;
  }

  void clearDoneTasks() {
    final currentTasks = Map<String, dynamic>.from(tasksNotifier.value);
    currentTasks.removeWhere((key, value) {
      bool isDone = value['type'] == 'done';
      if (!isDone && value['current'] != null && value['total'] != null) {
        if (value['current'] >= value['total']) isDone = true;
      }
      return isDone;
    });
    tasksNotifier.value = currentTasks;
  }
}