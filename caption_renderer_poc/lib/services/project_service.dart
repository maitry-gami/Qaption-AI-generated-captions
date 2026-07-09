import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/project_model.dart';

class ProjectService {
  static const String _fileName = 'projects.json';

  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<ProjectModel>> getProjects() async {
    final file = await _getFile();
    final bakFile = File('${file.path}.bak');

    try {
      if (!await file.exists()) {
        if (await bakFile.exists()) {
          await bakFile.copy(file.path);
        } else {
          return [];
        }
      }

      final String contents = await file.readAsString();
      final List<dynamic> jsonList = json.decode(contents);
      
      final projects = jsonList.map((json) => ProjectModel.fromJson(json)).toList();
      projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return projects;
    } catch (e) {
      print('Error reading projects: $e');
      if (await file.exists()) {
        await file.rename('${file.path}.corrupt_${DateTime.now().millisecondsSinceEpoch}');
      }
      if (await bakFile.exists()) {
        await bakFile.copy(file.path);
        return getProjects(); // Try again with bak
      }
      return [];
    }
  }

  Future<void> saveProject(ProjectModel project) async {
    try {
      final projects = await getProjects();
      
      final index = projects.indexWhere((p) => p.id == project.id);
      if (index >= 0) {
        projects[index] = project;
      } else {
        projects.insert(0, project);
      }

      final file = await _getFile();
      final bakFile = File('${file.path}.bak');
      final tempFile = File('${file.path}.tmp');
      
      final String jsonString = json.encode(projects.map((p) => p.toJson()).toList());
      
      // Atomic write
      await tempFile.writeAsString(jsonString, flush: true);
      if (await file.exists()) {
        await file.copy(bakFile.path);
      }
      await tempFile.rename(file.path);
    } catch (e) {
      print('Error saving project: $e');
    }
  }

  Future<void> deleteProject(String id) async {
    try {
      final projects = await getProjects();
      projects.removeWhere((p) => p.id == id);
      
      final file = await _getFile();
      final String jsonString = json.encode(projects.map((p) => p.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      print('Error deleting project: $e');
    }
  }
}
