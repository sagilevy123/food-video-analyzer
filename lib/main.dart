import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'google_auth_screen.dart';
import 'package:my_food_app/models/FilterCriteria.dart';
import 'package:my_food_app/widgets/details_logic.dart';
import 'package:my_food_app/screens/add_link_screen.dart';
import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:developer' as dev; // ייבוא כלי הלוגים של דארט

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. אתחול Firebase עם הגנה
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 3));
  } catch (_) {}

  // 2. הפעלת האפליקציה מיד! (זה ימנע את המסך הלבן)
  runApp(const FoodApp());

}

class FoodApp extends StatelessWidget {
  const FoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) {
            return const HomeScreen();
          }
          return const GoogleAuthScreen();
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // משתנה לניהול המאזין לשיתוף
  late StreamSubscription _intentDataStreamSubscription;
  FilterCriteria filters = FilterCriteria();
  String searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // רישום ה-Observer כדי לזהות חזרה לאפליקציה מרקע
    WidgetsBinding.instance.addObserver(this);

    // 1. האזנה לשיתוף כשהאפליקציה פתוחה ברקע (Stream)
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) {
        _handleSharedLink(value.first.path);
      }
    }, onError: (err) {
      print("Sharing error: $err");
    });

    // 2. בדיקה בזמן פתיחת האפליקציה מאפס (Initial)
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value != null && value.isNotEmpty) {
        _handleSharedLink(value.first.path);
      }
    });
  }

  // פונקציית התיקון הקריטית ל-iOS
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // בכל פעם שחוזרים מטיקטוק לאפליקציה (Resumed)
    if (state == AppLifecycleState.resumed) {
      ReceiveSharingIntent.instance.getInitialMedia().then((value) {
        if (value.isNotEmpty) {
          _handleSharedLink(value.first.path);
          // ניקוי כדי למנוע כפילויות בפתיחה הבאה
          ReceiveSharingIntent.instance.reset();
        }
      });
    }
  }

  void _handleSharedLink(String rawText) async {
  RegExp regExp = RegExp(r'(https?:\/\/[^\s]+)');
  var match = regExp.firstMatch(rawText);

  if (match != null) {
    String url = match.group(0)!;

    // הצגת הודעה מידית למשתמש
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("מזהה סרטון טיקטוק..."), backgroundColor: Colors.blue),
    );

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;

      // שמירה באוסף שמפעיל את ה-index.ts
      await FirebaseFirestore.instance.collection('tiktok_links').add({
        'url': url,
        'userId': userId,
        'status': 'pending', // זה מה שמפעיל את ה-AI בשרת!
        'createdAt': FieldValue.serverTimestamp(),
      });

      // הודעת הצלחה - בדיוק כמו ב-AddLinkScreen
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("נשלח לניתוח! המסעדה תופיע ברשימה בקרוב 🎉"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      print("Firebase Error: $e");
    }
  }
}

  void _toggleTag(String tag) {
    setState(() {
      if (filters.selectedTags.contains(tag)) {
        filters.selectedTags.remove(tag);
      } else {
        filters.selectedTags.add(tag);
      }
    });
  }

  void _showFilterDialog(String type, List<String> options) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Select ${type == 'city' ? 'City' : 'Cuisine'}",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text("All"),
              onTap: () {
                setState(() => type == 'city' ? filters.city = null : filters.cuisine = null);
                Navigator.pop(context);
              },
            ),
            ...options.map((opt) => ListTile(
                  title: Text(opt),
                  onTap: () {
                    setState(() => type == 'city' ? filters.city = opt : filters.cuisine = opt);
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // ניקוי כל המאזינים כדי למנוע דליפות זיכרון
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Foodie Map",
                                 style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1)),
                            const Text("Organizing your favorites has never been so easy",
                                 style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w400)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => MapScreen(filteredFilters: filters))
                        ),
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.blue,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16)),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
                      decoration: const InputDecoration(
                        hintText: "Search restaurants, notes...",
                        border: InputBorder.none,
                        icon: Icon(Icons.search, color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  _buildModernFilterButton(
                    icon: Icons.location_on_outlined,
                    label: filters.city ?? "City",
                    onTap: () => _showFilterDialog('city', ['Tel Aviv', 'Jerusalem', 'Haifa', 'Herzliya']),
                    isActive: filters.city != null,
                  ),
                  const SizedBox(width: 10),
                  _buildModernFilterButton(
                    icon: Icons.restaurant_outlined,
                    label: filters.cuisine ?? "Cuisine",
                    onTap: () => _showFilterDialog('cuisine', ['Burger', 'Pizza', 'Asian', 'Meat']),
                    isActive: filters.cuisine != null,
                  ),
                  const SizedBox(width: 12),
                  ...['Cheap', 'Tasty', 'Romantic', 'Kosher'].map((tag) {
                    final isSelected = filters.selectedTags.contains(tag);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _toggleTag(tag),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isSelected ? Colors.black : Colors.grey[200]!),
                          ),
                          child: Text(tag, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF5F5F5)),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('restaurants')
                    .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  var allDocs = snapshot.data!.docs;

                  var filteredDocs = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    bool matchesSearch = searchQuery.isEmpty ||
                        (data['name'] ?? '').toString().toLowerCase().contains(searchQuery);
                    bool matchesCity = filters.city == null || data['address'].toString().contains(filters.city!);
                    bool matchesCuisine = filters.cuisine == null || data['cuisine'] == filters.cuisine;
                    bool matchesTags = filters.selectedTags.isEmpty ||
                        filters.selectedTags.any((tag) =>
                            (data['global_summary']?['decision_chips'] as List?)?.contains(tag) ?? false);

                    return matchesSearch && matchesCity && matchesCuisine && matchesTags;
                  }).toList();

                  final seenNames = <String>{};
                  final List<QueryDocumentSnapshot> uniqueDocs = filteredDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final String name = (data['name'] ?? '').toString().toLowerCase().trim();
                    if (seenNames.contains(name)) return false;
                    seenNames.add(name);
                    return true;
                  }).toList();

                  if (uniqueDocs.isEmpty) return const Center(child: Text("No restaurants found matching filters"));

                  return ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: uniqueDocs.length,
                    itemBuilder: (context, index) {
                      final doc = uniqueDocs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      data['docId'] = doc.id;

                      return Dismissible(
                        key: Key(doc.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) {
                          FirebaseFirestore.instance.collection('restaurants').doc(doc.id).delete();
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
                        ),
                        child: _buildModernCard(context, data),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AddLinkScreen())
        ),
        label: const Text("Add New"),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.blue,
        elevation: 4,
      ),
    );
  }

  Widget _buildModernFilterButton({required IconData icon, required String label, required VoidCallback onTap, required bool isActive}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue[50] : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isActive ? Colors.blue[200]! : Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.blue[700] : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isActive ? Colors.blue[700] : Colors.black87)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildModernCard(BuildContext context, Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(data['name'] ?? 'Restaurant', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        subtitle: Text("${data['cuisine']} • ${data['address']}", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
        onTap: () => showDetails(context, data),
      ),
    );
  }
}

class MapScreen extends StatelessWidget {
  final FilterCriteria filteredFilters;
  const MapScreen({super.key, required this.filteredFilters});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Filtered Map')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('restaurants')
            .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          Set<Marker> markers = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final loc = data['location'] as Map<String, dynamic>;
            return Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(loc['lat'], loc['lng']),
              onTap: () => showDetails(context, data),
            );
          }).toSet();

          return GoogleMap(
            initialCameraPosition: const CameraPosition(target: LatLng(32.0853, 34.7818), zoom: 11),
            markers: markers,
          );
        },
      ),
    );
  }
}

class LinkSharingService {
  static const platform = MethodChannel('com.example.app/sharing');

  static Future<String?> getSharedLink() async {
    try {
      // אנחנו מבקשים מה-iOS את הערך ששמרנו תחת המפתח last_shared_link
      final String? sharedLink = await platform.invokeMethod('getSharedLink');
      return sharedLink;
    } on PlatformException catch (e) {
      print("Failed to get shared link: '${e.message}'.");
      return null;
    }
  }
}