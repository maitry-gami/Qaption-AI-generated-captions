import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _phoneNumber = 'Loading...';
  String _userName = 'Qaption User';
  bool _isLoading = false;
  int _exportTimeInSeconds = 600;

  String _formatExportTime(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    int s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  
  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    
    final exportTime = prefs.getInt('export_time');
    if (exportTime != null) {
      setState(() {
        _exportTimeInSeconds = exportTime;
      });
    } else {
      // Default to 10 minutes (600 seconds) if not set
      prefs.setInt('export_time', 600);
      setState(() {
        _exportTimeInSeconds = 600;
      });
    }

    if (user != null) {
      setState(() {
        _phoneNumber = user.phoneNumber ?? 'Unknown Number';
      });
      
      final token = prefs.getString('auth_token');
      
      if (token != null) {
        try {
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
              setState(() {
                _userName = data['user']['name'];
              });
            }
          }
        } catch (e) {
          debugPrint('Error fetching profile: $e');
        }
      }
    }
  }

  Future<void> _editUserName() async {
    final TextEditingController nameController = TextEditingController(text: _userName == 'Qaption User' ? '' : _userName);
    
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Edit Name', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter your name',
              hintStyle: const TextStyle(color: Colors.grey),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[800]!)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF8B5CF6))),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty) {
                  Navigator.pop(context);
                  await _updateUserName(newName);
                }
              },
              child: const Text('Save', style: TextStyle(color: Color(0xFF8B5CF6))),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateUserName(String newName) async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    if (token != null) {
      try {
        final response = await http.put(
          Uri.parse('http://192.168.1.11:3005/qaption/auth/profile'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'name': newName}),
        );
        
        if (response.statusCode == 200) {
          setState(() {
            _userName = newName;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name updated successfully')));
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update name')));
          }
        }
      } catch (e) {
        debugPrint('Error updating name: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error')));
        }
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F11),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFFFFFFFF), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            // Profile Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF222225),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 64,
                color: Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _editUserName,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _userName,
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_rounded, color: Color(0xFF9E9E9E), size: 18),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _phoneNumber,
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 32),

            // Balance Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF222225),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF2C2C2E)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'YOUR BALANCE',
                    style: TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatExportTime(_exportTimeInSeconds),
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Available AI export time',
                    style: TextStyle(
                      color: Color(0xFF9E9E9E),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              backgroundColor: const Color(0xFF222225),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              title: const Text('Top Up Credits', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              content: const Text('Email on : xyz@gmail.com to get more credits.', style: TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK', style: TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Top Up',
                        style: TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Account & App Settings
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ACCOUNT & APP',
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF222225),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF2C2C2E)),
              ),
              child: Column(
                children: [

                  _buildListTile(Icons.headset_mic_outlined, 'Support Team'),
                  const Divider(color: Color(0xFF2C2C2E), height: 1, indent: 56),
                  _buildListTile(Icons.menu_book_rounded, 'User Guide'),
                  const Divider(color: Color(0xFF2C2C2E), height: 1, indent: 56),
                  _buildListTile(Icons.shield_outlined, 'Privacy Policy'),
                  const Divider(color: Color(0xFF2C2C2E), height: 1, indent: 56),
                  _buildListTile(Icons.info_outline_rounded, 'About Us'),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Version Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'App Version v1.0.1',
                      style: TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Last updated Jun 25, 2026',
                      style: TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
                  ),
                  child: const Text(
                    'v1.0.0 (Stable)',
                    style: TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Logout Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: TextButton(
                onPressed: _logout,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Log Out',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Footer
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(IconData icon, String title) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Color(0xFFFFFFFF), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF9E9E9E), size: 16),
      onTap: () {},
    );
  }
}
