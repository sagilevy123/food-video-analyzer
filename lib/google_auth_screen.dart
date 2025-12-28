import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';

class GoogleAuthScreen extends StatefulWidget {
  const GoogleAuthScreen({super.key});

  @override
  State<GoogleAuthScreen> createState() => _GoogleAuthScreenState();
}

class _GoogleAuthScreenState extends State<GoogleAuthScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // אתחול המופע היחיד
    GoogleSignIn.instance.initialize();
  }

Future<void> _signInWithGoogle() async {
  setState(() => _isLoading = true);

  try {
    // 1. אתחול ופתיחת חלון גוגל
    await GoogleSignIn.instance.initialize();
    final response = await GoogleSignIn.instance.authenticate(scopeHint: ['email']);

    // 2. קבלת אובייקט האימות
    final auth = await response.authentication;

    // 3. חילוץ ה-Tokens בדרך היחידה שעובדת בגרסה שלך
    // ה-idToken הוא פשוט המחרוזת שראינו ב-Debug שלך
    final String idToken = auth.toString().replaceFirst('GoogleSignInAuthentication: ', '');

    // בגרסה הזו, ה-accessToken בדרך כלל לא נחוץ ל-Firebase אם יש idToken תקין
    // אבל אנחנו ננסה לשלוף אותו בגישה דינמית בטוחה
    String? accessToken;
    try {
      accessToken = (auth as dynamic).accessToken;
    } catch (_) {
      accessToken = null;
    }

    // 4. יצירת ה-Credential ושליחה ל-Firebase
    final AuthCredential credential = GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: accessToken,
    );

    await FirebaseAuth.instance.signInWithCredential(credential);
    print("Successfully signed in to Firebase!");

  } catch (e) {
    debugPrint("Final error: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed. Check terminal.")),
      );
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.map_rounded, size: 100, color: Colors.blue),
              const SizedBox(height: 20),
              const Text("Foodie Map", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 60),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _signInWithGoogle,
                  icon: const Icon(Icons.login),
                  label: const Text("Sign in with Google"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}