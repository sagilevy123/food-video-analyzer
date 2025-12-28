import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'google_auth_screen.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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

class FilterCriteria {
  String? city;
  String? cuisine;
  String? reviewer;
  List<String> selectedTags = [];

  bool get isEmpty => city == null && cuisine == null && reviewer == null && selectedTags.isEmpty;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FilterCriteria filters = FilterCriteria();

  void _toggleTag(String tag) {
    setState(() {
      if (filters.selectedTags.contains(tag)) {
        filters.selectedTags.remove(tag);
      } else {
        filters.selectedTags.add(tag);
      }
    });
  }

  void _updateFilter(String type, String? value) {
    setState(() {
      if (type == 'city') filters.city = value;
      if (type == 'cuisine') filters.cuisine = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<String> availableTags = ['Cheap', 'Tasty', 'Atmosphere', 'Romantic', 'Kosher'];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: false, // מצמיד את הטקסט לשמאל
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Foodie Map',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 20)),
            // הצגת שם המשתמש המחובר מתחת לכותרת
            Text(
              "Hello, ${FirebaseAuth.instance.currentUser?.displayName ?? 'User'}",
              style: TextStyle(color: Colors.blue[700], fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          // הצגת תמונת הפרופיל של המשתמש (אם קיימת)
          if (FirebaseAuth.instance.currentUser?.photoURL != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: CircleAvatar(
                radius: 15,
                backgroundImage: NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.blue, size: 28),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddLinkScreen())),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // שורת סינון מאוחדת וקטנה יותר
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Dropdowns קטנים יותר
                _buildTinyDropdown('City', 'city', ['Tel Aviv', 'Jerusalem', 'Haifa']),
                const SizedBox(width: 8),
                _buildTinyDropdown('Cuisine', 'cuisine', ['Burger', 'Pizza', 'Asian', 'Meat']),
                const SizedBox(width: 12),
                const VerticalDivider(width: 1),
                const SizedBox(width: 12),

                // תגיות וסינון מבקרים באותה שורה גלילה
                ...availableTags.map((tag) {
                  final isSelected = filters.selectedTags.contains(tag);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(tag, style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      onSelected: (_) => _toggleTag(tag),
                      selectedColor: Colors.blue[100],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),

          // סינון מבקרים קומפקטי (ללא כותרת גדולה)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('restaurants')
                .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              final reviewers = snapshot.data!.docs
                  .map((doc) => (doc.data() as Map<String, dynamic>)['reviewerName']?.toString())
                  .where((name) => name != null && name != "TikTok User")
                  .toSet().toList();

              if (reviewers.isEmpty) return const SizedBox();

              return Container(
                height: 40,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const Center(child: Text("By:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text("All", style: TextStyle(fontSize: 12)),
                      selected: filters.reviewer == null,
                      onSelected: (_) => setState(() => filters.reviewer = null),
                    ),
                    ...reviewers.map((name) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(name!, style: const TextStyle(fontSize: 12)),
                        selected: filters.reviewer == name,
                        onSelected: (selected) => setState(() => filters.reviewer = selected ? name : null),
                        selectedColor: Colors.orange[100],
                      ),
                    )),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),

          // 4. רשימת המסעדות
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('restaurants')
                  .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  bool matchCity = filters.city == null || (data['address'] ?? '').toString().toLowerCase().contains(filters.city!.toLowerCase());
                  bool matchCuisine = filters.cuisine == null || (data['cuisine'] ?? '') == filters.cuisine;
                  bool matchReviewer = filters.reviewer == null || data['reviewerName'] == filters.reviewer;

                  List resTags = (data['recommendation_tags'] as List? ?? []).map((t) => t.toString().toLowerCase()).toList();
                  bool matchTags = filters.selectedTags.every((tag) => resTags.contains(tag.toLowerCase()));

                  return matchCity && matchCuisine && matchTags && matchReviewer;
                }).toList();

                if (docs.isEmpty) return _buildEmptyState();

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    return _buildModernCard(context, data);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MapScreen(filteredFilters: filters))),
        label: const Text('Map View', style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.map_outlined),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildModernCard(BuildContext context, Map<String, dynamic> data) {
    String formattedDate = "";
    if (data['createdAt'] != null) {
      DateTime dt = (data['createdAt'] as Timestamp).toDate();
      formattedDate = DateFormat('dd/MM/yyyy').format(dt);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(data['name'] ?? 'Restaurant', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            if (formattedDate.isNotEmpty)
              Text(formattedDate, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person, size: 14, color: Colors.blue[300]),
                const SizedBox(width: 4),
                Text(data['reviewerName'] ?? 'TikTok User',
                  style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Text("${data['cuisine']} • ${data['address']}", style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: (data['recommendation_tags'] as List? ?? []).take(3).map((t) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4)),
                child: Text(t, style: const TextStyle(fontSize: 10, color: Colors.blue)),
              )).toList(),
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: () => _showDetails(context, data),
      ),
    );
  }

Widget _buildTinyDropdown(String label, String type, List<String> options) {
    String? currentValue = type == 'city' ? filters.city : filters.cuisine;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 35, // גובה נמוך יותר
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: currentValue,
          hint: Text(label, style: const TextStyle(fontSize: 12)),
          items: [null, ...options].map((v) => DropdownMenuItem(value: v, child: Text(v ?? 'All', style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (val) => _updateFilter(type, val),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("No restaurants match your filters", style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
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

          var filteredDocs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;

            bool matchCity = filteredFilters.city == null || (data['address'] ?? '').toString().toLowerCase().contains(filteredFilters.city!.toLowerCase());
            bool matchCuisine = filteredFilters.cuisine == null || (data['cuisine'] ?? '').toString().toLowerCase() == filteredFilters.cuisine!.toLowerCase();
            bool matchReviewer = filteredFilters.reviewer == null || data['reviewerName'] == filteredFilters.reviewer;

            List resTags = (data['recommendation_tags'] as List? ?? []).map((t) => t.toString().toLowerCase()).toList();
            bool matchTags = filteredFilters.selectedTags.every((tag) => resTags.contains(tag.toLowerCase()));

            return matchCity && matchCuisine && matchTags && matchReviewer;
          }).toList();

          Set<Marker> markers = filteredDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final loc = data['location'] as Map<String, dynamic>;
            return Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(loc['lat'], loc['lng']),
              onTap: () => _showDetails(context, data),
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

// שאר פונקציות העזר (showDetails, AddLinkScreen וכו') נשארות כפי שהיו
void _showDetails(BuildContext context, Map<String, dynamic> data) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      final String websiteUrl = data['website'] ?? '';
      final String priceLevel = data['price_level'] ?? 'not-known';
      final String sentimentScore = data['sentiment_score'] ?? 'neutral';

      Color getPriceColor() {
        switch (priceLevel) {
          case 'cheap': return Colors.green;
          case 'normal': return Colors.blue;
          case 'expensive': return Colors.red;
          default: return Colors.orange;
        }
      }

      Color getSentimentColor() {
        switch (sentimentScore) {
          case 'positive': return Colors.green;
          case 'negative': return Colors.red;
          default: return Colors.orange;
        }
      }

      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: websiteUrl.isNotEmpty ? () => launchUrl(Uri.parse(websiteUrl)) : null,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              data['name'] ?? 'Restaurant',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                decoration: websiteUrl.isNotEmpty ? TextDecoration.underline : null,
                                color: websiteUrl.isNotEmpty ? Colors.blue.shade900 : Colors.black,
                              ),
                            ),
                          ),
                          if (websiteUrl.isNotEmpty)
                            const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.open_in_new, size: 16, color: Colors.blue)),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: getPriceColor().withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: getPriceColor())),
                    child: Text(priceLevel == 'not-known' ? "? Price" : priceLevel.toUpperCase(), style: TextStyle(color: getPriceColor(), fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
              if (data['reviewerName'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.person, size: 14, color: Colors.blue[300]),
                      const SizedBox(width: 4),
                      Text("Review by: ${data['reviewerName']}", style: TextStyle(fontSize: 13, color: Colors.blue[700], fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (data['recommendation_essence'] != null)
                Text(data['recommendation_essence'], style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.4)),
              const SizedBox(height: 16),
              if (data['community_sentiment'] != null && data['community_sentiment'].toString().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: getSentimentColor(), shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          const Text("Community Voice", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(data['community_sentiment'], style: TextStyle(color: Colors.blue.shade900, fontSize: 13, height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Divider(),
              const SizedBox(height: 8),
              _buildActionButton(Icons.directions, 'Get Directions', Colors.blue, () async {
                 final loc = data['location'];
                 final url = "http://maps.google.com/?q=${loc['lat']},${loc['lng']}";
                 await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              }),
              _buildActionButton(Icons.play_circle_fill, 'Watch TikTok Review', Colors.black, () => launchUrl(Uri.parse(data['videoUrl'] ?? ''))),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color.withOpacity(0.5))),
      ),
    ),
  );
}

class AddLinkScreen extends StatefulWidget {
  const AddLinkScreen({super.key});
  @override
  State<AddLinkScreen> createState() => _AddLinkScreenState();
}

class _AddLinkScreenState extends State<AddLinkScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;

  void _submit() async {
    if (_controller.text.isEmpty) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isSending = true);
    await FirebaseFirestore.instance.collection('tiktok_links').add({
      'url': _controller.text.trim(),
      'status': 'pending',
      'userId': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Recommendation')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Paste TikTok link here')),
            const SizedBox(height: 20),
            _isSending ? const CircularProgressIndicator() : ElevatedButton(onPressed: _submit, child: const Text('Submit')),
          ],
        ),
      ),
    );
  }
}