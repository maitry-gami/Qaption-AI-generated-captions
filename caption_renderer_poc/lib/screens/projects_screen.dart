import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // To access MyHomePage
import '../models/project_model.dart';
import '../services/project_service.dart';
import 'profile_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> with SingleTickerProviderStateMixin {
  final ImagePicker _imagePicker = ImagePicker();
  final ProjectService _projectService = ProjectService();
  List<ProjectModel> _projects = [];
  int _selectedIndex = 0;
  String _userName = '';
  
  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat(reverse: true);
    _loadProjects();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null) {
        final response = await http.get(
          Uri.parse('http://192.168.1.11:3005/qaption/auth/profile'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['user'] != null && data['user']['name'] != null) {
            if (mounted) {
              setState(() {
                _userName = data['user']['name'];
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching user name: $e');
    }
  }

  Future<void> _loadProjects() async {
    final projects = await _projectService.getProjects();
    setState(() {
      _projects = projects;
    });
  }

  Future<void> fetchProtectedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No token found! Please log in first.')),
        );
      }
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('http://10.124.51.120:3005/qaption/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ SUCCESS: ${response.body}'),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❌ FAILED: ${response.statusCode} - ${response.body}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showCreateProjectDialog() async {
    final TextEditingController nameController = TextEditingController();

    final String? projectName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2E),
          title: const Text(
            'New Project',
            style: TextStyle(color: Color(0xFFFFFFFF)),
          ),
          content: TextField(
            controller: nameController,
            style: const TextStyle(color: Color(0xFFFFFFFF)),
            decoration: const InputDecoration(
              hintText: 'Enter project name',
              hintStyle: TextStyle(color: Color(0xFF9E9E9E)),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF9E9E9E)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF8B5CF6)),
              ),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF9E9E9E)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, nameController.text.trim());
                }
              },
              child: const Text(
                'Next',
                style: TextStyle(color: Color(0xFFFFFFFF)),
              ),
            ),
          ],
        );
      },
    );

    if (projectName != null && projectName.isNotEmpty) {
      _pickVideoAndCreate(projectName);
    }
  }

  Future<void> _pickVideoAndCreate(String projectName) async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );

      if (video != null && mounted) {
        final newProject = ProjectModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: projectName,
          videoPath: video.path,
          updatedAt: DateTime.now(),
        );

        await _projectService.saveProject(newProject);
        await _loadProjects(); // Refresh list

        if (!mounted) return;

        // Navigate to the editor with the picked video path
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (context) => MyHomePage(project: newProject),
              ),
            )
            .then((_) {
              if (mounted) _loadProjects();
            });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick video: $e')));
      }
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.day} ${_getMonth(date.month)} ${date.year}';
  }

  String _getMonth(int month) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return months[month - 1];
  }

  Future<void> _showDeleteConfirmation(ProjectModel project) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2E),
          title: const Text(
            'Delete Project',
            style: TextStyle(color: Color(0xFFFFFFFF)),
          ),
          content: Text(
            'Are you sure you want to delete "${project.name}"?',
            style: const TextStyle(color: Color(0xFFFFFFFF)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF9E9E9E)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFFFFFFF)),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _projectService.deleteProject(project.id);
      _loadProjects();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Deepest black-indigo
      body: Stack(
        children: [
          // Dynamic Animated Background
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              final value = _bgController.value;
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.5 * (value - 0.5), -0.5 * value),
                    radius: 1.5,
                    colors: [
                      const Color(0xFF3B1D50).withOpacity(0.4),
                      const Color(0xFF1E1030).withOpacity(0.3),
                      const Color(0xFF09090B),
                    ],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF8B5CF6).withOpacity(0.15 * value),
                        Colors.transparent,
                        const Color(0xFF4A1D6E).withOpacity(0.15 * (1 - value)),
                      ],
                      begin: Alignment(-1.0 + 2.0 * value, -1.0),
                      end: Alignment(1.0 - 2.0 * value, 1.0),
                    ),
                  ),
                ),
              );
            },
          ),
          
          // Content
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Premium Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userName.isNotEmpty ? 'Hello, $_userName' : 'Hello,',
                            style: const TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Colors.white, Color(0xFFD4D4D8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: const Text(
                              'Your Projects',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ProfileScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8B5CF6).withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const CircleAvatar(
                            radius: 20,
                            backgroundColor: Color(0xFF18181B),
                            child: Icon(Icons.person_outline_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Projects List
                Expanded(
                  child: _projects.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.video_library_rounded,
                                  size: 48,
                                  color: Color(0xFF8B5CF6),
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'No Projects Yet',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Tap the + button to create your\nfirst caption masterpiece.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFA1A1AA),
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 100),
                          physics: const BouncingScrollPhysics(),
                          itemCount: _projects.length,
                          itemBuilder: (context, index) {
                            final project = _projects[index];
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 600 + (index * 150).clamp(0, 600).toInt()),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return Transform.translate(
                                  offset: Offset(0, 40 * (1 - value)),
                                  child: Opacity(opacity: value, child: child),
                                );
                              },
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context)
                                      .push(MaterialPageRoute(builder: (context) => MyHomePage(project: project)))
                                      .then((_) {
                                    if (mounted) _loadProjects();
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 20),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(28),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                      child: Container(
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.white.withOpacity(0.08),
                                              Colors.white.withOpacity(0.03),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(28),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.1),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // Thumbnail substitute
                                            Container(
                                              width: 72,
                                              height: 72,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [Color(0xFF2E1A47), Color(0xFF18181B)],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.2),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: Color(0xFF8B5CF6),
                                                  size: 32,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 20),
                                            // Project Info
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    project.name,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w700,
                                                      letterSpacing: 0.3,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withOpacity(0.05),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Text(
                                                      'Edited ${_formatDate(project.updatedAt)}',
                                                      style: TextStyle(
                                                        color: const Color(0xFFA1A1AA),
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Delete Button
                                            IconButton(
                                              icon: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent.withOpacity(0.1),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: Colors.redAccent,
                                                  size: 20,
                                                ),
                                              ),
                                              onPressed: () => _showDeleteConfirmation(project),
                                              splashRadius: 24,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 24.0, right: 8.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withOpacity(0.5),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FloatingActionButton.extended(
            onPressed: _showCreateProjectDialog,
            backgroundColor: const Color(0xFF8B5CF6),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            label: const Text(
              'New Project',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
      // We remove bottomNavigationBar for a cleaner, full-screen floating feel,
      // relying on the header profile icon for navigation!
    );
  }
}
