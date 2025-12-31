import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'google_auth_screen.dart';
import 'package:intl/intl.dart';
import 'package:my_food_app/models/FilterCriteria.dart';
import 'package:my_food_app/widgets/ui_components.dart';
import 'package:my_food_app/widgets/details_logic.dart';
import 'package:my_food_app/services/url_service.dart';

/// The entry point of the Flutter application.
/// It ensures all bindings are initialized and Firebase is ready before launching.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const FoodApp());
}

/// The root widget of the Foodie Map application.
/// Sets the global visual theme and determines the initial screen based on authentication state.
class FoodApp extends StatelessWidget {
  const FoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      // StreamBuilder listens to the user's authentication status in real-time.
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          // If the user is logged in, show the HomeScreen, otherwise show the Auth screen.
          if (snapshot.hasData) {
            return const HomeScreen();
          }
          return const GoogleAuthScreen();
        },
      ),
    );
  }
}


// --- MAIN SCREENS ---

/// The central hub of the app, containing the searchable list of restaurants and filter options.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FilterCriteria filters = FilterCriteria();
  String searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  /// Adds or removes a tag from the active filter list.
  void _toggleTag(String tag) {
    setState(() {
      if (filters.selectedTags.contains(tag)) {
        filters.selectedTags.remove(tag);
      } else {
        filters.selectedTags.add(tag);
      }
    });
  }

  /// Displays a selection dialog for predefined filtering categories (City/Cuisine).
  void _showFilterDialog(String type, List<String> options) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Select ${type == 'city' ? 'City' : 'Cuisine'}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // HEADER: App branding and "Add Link" navigation
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Expanded Column handles the title and tagline without horizontal overflow.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Foodie Map",
                                 style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1)),
                            Text("Organizing your favorites has never been so easy",
                                 style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w400)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddLinkScreen())),
                        icon: const Icon(Icons.add_circle, color: Colors.blue, size: 32),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // SEARCH BAR: Triggers real-time filtering of the displayed list.
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
            // FILTERS: Horizontal scrollable chips for city, cuisine, and tags.
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
            // LIST VIEW: Fetches user-specific restaurant data from Cloud Firestore.
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('restaurants')
                    .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  var allDocs = snapshot.data!.docs;

                  // Manual client-side filtering based on search query.
                  var filteredDocs = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return searchQuery.isEmpty ||
                           (data['name'] ?? '').toString().toLowerCase().contains(searchQuery);
                  }).toList();

                  // Prevents duplicate entries from appearing in the UI list.
                  final seenNames = <String>{};
                  final List<QueryDocumentSnapshot> uniqueDocs = filteredDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final String name = (data['name'] ?? '').toString().toLowerCase().trim();
                    if (seenNames.contains(name)) {
                      return false;
                    } else {
                      seenNames.add(name);
                      return true;
                    }
                  }).toList();

                  if (uniqueDocs.isEmpty) return const Center(child: Text("No restaurants found"));

                  return ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: uniqueDocs.length,
                    itemBuilder: (context, index) {
                      final doc = uniqueDocs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      data['docId'] = doc.id;

                      // Dismissible allows users to delete an entry with a swipe.
                      return Dismissible(
                        key: Key(doc.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) {
                          FirebaseFirestore.instance.collection('restaurants').doc(doc.id).delete();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("${data['name']} removed from your list")),
                          );
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
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MapScreen(filteredFilters: filters))),
        label: const Text("Map"),
        icon: const Icon(Icons.map),
        backgroundColor: Colors.black,
      ),
    );
  }

  /// Builder for specialized filter category buttons.
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

  /// Builder for individual restaurant summary cards.
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

// --- UTILITY SCREENS ---

/// A full-screen map interface displaying markers for each saved restaurant.
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
          // Transform restaurant documents into Google Maps markers.
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

/// A screen for inputting new social media links for AI analysis.
class AddLinkScreen extends StatefulWidget {
  const AddLinkScreen({super.key});
  @override
  State<AddLinkScreen> createState() => _AddLinkScreenState();
}

class _AddLinkScreenState extends State<AddLinkScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;

  /// Adds a new URL record to Firestore, triggering the backend Cloud Function.
  void _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    setState(() => _isSending = true);

    await FirebaseFirestore.instance.collection('tiktok_links').add({
      'url': url,
      'status': 'pending',
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Recommendation')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Paste video link here')),
            const SizedBox(height: 20),
            _isSending ? const CircularProgressIndicator() : ElevatedButton(onPressed: _submit, child: const Text('Submit')),
          ],
        ),
      ),
    );
  }
}
