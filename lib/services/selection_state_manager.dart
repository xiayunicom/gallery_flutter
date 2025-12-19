// lib/services/selection_state_manager.dart
import 'package:flutter/foundation.dart';

class SelectionStateManager extends ChangeNotifier {
  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};
  int? _lastInteractionIndex;

  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedPaths => _selectedPaths;
  int? get lastInteractionIndex => _lastInteractionIndex;

  void toggleSelectionMode() {
    _isSelectionMode = !_isSelectionMode;
    if (!_isSelectionMode) {
      _selectedPaths.clear();
      _lastInteractionIndex = null;
    }
    notifyListeners();
  }

  void setSelectionMode(bool value) {
    if (_isSelectionMode != value) {
      _isSelectionMode = value;
      if (!value) {
        _selectedPaths.clear();
        _lastInteractionIndex = null;
      }
      notifyListeners();
    }
  }

  void selectAll(List<String> allPaths) {
    if (!_isSelectionMode) _isSelectionMode = true;
    _selectedPaths.addAll(allPaths);
    _lastInteractionIndex = allPaths.length - 1;
    notifyListeners();
  }

  void clearSelection() {
    _selectedPaths.clear();
    _lastInteractionIndex = null;
    _isSelectionMode = false;
    notifyListeners();
  }

  void toggleItem(String path, int index) {
    if (_selectedPaths.contains(path)) {
      _selectedPaths.remove(path);
      if (_selectedPaths.isEmpty) {
        _isSelectionMode = false;
        _lastInteractionIndex = null;
      } else {
        _lastInteractionIndex = index;
      }
    } else {
      _selectedPaths.add(path);
      _isSelectionMode = true;
      _lastInteractionIndex = index;
    }
    notifyListeners();
  }

  void updateSelectionState(String path, bool isSelected) {
    if (isSelected) {
      _selectedPaths.add(path);
    } else {
      _selectedPaths.remove(path);
    }
    // Note: This method might not auto-update mode or index, usually used in batch/drag
    notifyListeners();
  }

  void setLastInteractionIndex(int? index) {
    _lastInteractionIndex = index;
    // No notify needed strictly if used for internal logic, but usually good to notify
  }

  bool isSelected(String path) {
    return _selectedPaths.contains(path);
  }
}
