import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'projects_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  final List<String> _countryCodes = ['+1', '+44', '+91', '+61', '+81', '+49', '+33', '+86', '+55'];
  String _selectedCountryCode = '+91';

  String? _verificationId;
  int? _resendToken;
  bool _otpSent = false;
  bool _isVerifying = false;
  bool _obscureOtp = true;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic)
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _sendOtpBtn() {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit number.')),
      );
      return;
    }
    _sendOtp();
  }

  void _resendOtpBtn() {
    _sendOtp(isResend: true);
  }

  Future<void> _sendOtp({bool isResend = false}) async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.length != 10) return;

    setState(() {
      _isVerifying = true;
    });

    final phoneNumber = '$_selectedCountryCode$rawPhone';

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: isResend ? _resendToken : null,
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (credential.smsCode != null) {
            _passwordController.text = credential.smsCode!;
          }
          await _signInWithFirebase(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              _isVerifying = false;
              _otpSent = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Verification Failed: ${e.message}')),
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _isVerifying = false;
              _otpSent = true;
              _verificationId = verificationId;
              _resendToken = resendToken;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('OTP Sent via SMS!')),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _isVerifying = false;
            });
          }
        },
      );
    } catch (e) {
      setState(() {
        _isVerifying = false;
        _otpSent = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _login() async {
    final rawPhone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (rawPhone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both phone number and OTP.')),
      );
      return;
    }

    if (_verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for OTP to be sent or enter a valid 10-digit number.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: password,
      );
      await _signInWithFirebase(credential);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid OTP or error: ${e.message}')),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _signInWithFirebase(PhoneAuthCredential credential) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await userCredential.user?.getIdToken();
      if (idToken != null) {
        await _loginBackend(idToken);
      } else {
        throw Exception("Failed to retrieve ID Token");
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Firebase Sign In Failed: ${e.message}')),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _loginBackend(String idToken) async {
    final rawPhone = _phoneController.text.trim();
    final phoneNumber = '$_selectedCountryCode$rawPhone';

    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.11:3005/qaption/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phoneNumber': phoneNumber,
          'idToken': idToken,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Success
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        
        if (data['accessToken'] != null) {
          await prefs.setString('auth_token', data['accessToken']);
        } else if (data['token'] != null) {
          await prefs.setString('auth_token', data['token']);
        }

        if (data['refreshToken'] != null) {
          await prefs.setString('refresh_token', data['refreshToken']);
        }
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const ProjectsScreen()),
          );
        }
      } else {
        // Error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backend Login failed: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting to server: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F11),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF261D3D).withOpacity(0.6),
              const Color(0xFF0F0F11),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF222225),
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: const Color(0xFF2C2C2E), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withOpacity(0.15),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Image.asset('assets/logo.png', width: 72, height: 72),
                ),
                const SizedBox(height: 32),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFFFFFF), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  child: Text(
                    'QAPTION',
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4.0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to access your projects',
                  style: TextStyle(
                    color: Color(0xFF9E9E9E),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 48),
                Row(
                  children: [
                    Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222225),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF2C2C2E)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCountryCode,
                          dropdownColor: const Color(0xFF222225),
                          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9E9E9E)),
                          style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16, fontWeight: FontWeight.w600),
                          items: _countryCodes.map((String code) {
                            return DropdownMenuItem<String>(
                              value: code,
                              child: Text(code),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedCountryCode = newValue!;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16, fontWeight: FontWeight.w600),
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: 'Phone Number',
                          hintStyle: const TextStyle(color: Color(0xFF9E9E9E)),
                          filled: true,
                          fillColor: const Color(0xFF222225),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(color: Color(0xFF2C2C2E)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_otpSent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16, fontWeight: FontWeight.w600),
                    obscureText: _obscureOtp,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'OTP Code',
                      hintStyle: const TextStyle(color: Color(0xFF9E9E9E)),
                      filled: true,
                      fillColor: const Color(0xFF222225),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureOtp ? Icons.visibility_off : Icons.visibility,
                          color: Color(0xFF9E9E9E),
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureOtp = !_obscureOtp;
                          });
                        },
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Color(0xFF2C2C2E)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isVerifying ? null : _resendOtpBtn,
                      child: Text(
                        _isVerifying ? 'Sending...' : 'Resend OTP',
                        style: const TextStyle(color: Color(0xFF9E9E9E), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Color(0xFFFFFFFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 8,
                      shadowColor: const Color(0xFF8B5CF6).withOpacity(0.5),
                    ),
                    onPressed: (_isLoading || _isVerifying) 
                        ? null 
                        : (_otpSent ? _login : _sendOtpBtn),
                    child: (_isLoading || _isVerifying)
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Color(0xFFFFFFFF), strokeWidth: 3),
                          )
                        : Text(
                            _otpSent ? 'Verify OTP' : 'Send OTP',
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}
