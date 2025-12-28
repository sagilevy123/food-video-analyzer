import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
      home: const HomeScreen(),
    );
  }
}

class FilterCriteria {
  String? city;
  String? cuisine;
  String? tag;
  bool get isEmpty => city == null && cuisine == null && tag == null;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FilterCriteria filters = FilterCriteria();

  void _updateFilter(String type, String? value) {
    setState(() {
      if (type == 'city') filters.city = value;
      if (type == 'cuisine') filters.cuisine = value;
      if (type == 'tag') filters.tag = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foodie Map', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddLinkScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterDropdown('City', 'city', ['Tel Aviv', 'Jerusalem', 'Haifa', 'Rishon LeTsiyon']),
                const SizedBox(width: 8),
                _buildFilterDropdown('Cuisine', 'cuisine', ['Burger', 'Pizza', 'Asian', 'Schnitzel', 'Meat']),
                const SizedBox(width: 8),
                _buildFilterDropdown('Tag', 'tag', ['Cheap', 'Tasty', 'Atmosphere', 'Romantic', 'Kosher']),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                // Modern Case-Insensitive Filtering
                var docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  bool matchCity = filters.city == null ||
                      (data['address'] ?? '').toString().toLowerCase().contains(filters.city!.toLowerCase());

                  bool matchCuisine = filters.cuisine == null ||
                      (data['cuisine'] ?? '').toString().toLowerCase() == filters.cuisine!.toLowerCase();

                  bool matchTag = filters.tag == null ||
                      (data['recommendation_tags'] as List? ?? []).any((t) => t.toString().toLowerCase() == filters.tag!.toLowerCase());

                  return matchCity && matchCuisine && matchTag;
                }).toList();

                if (docs.isEmpty) return const Center(child: Text('No restaurants found for these filters'));

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        title: Text(data['name'] ?? 'Restaurant', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${data['cuisine'] ?? 'General'} • ${data['address'] ?? 'No Address'}"),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showDetails(context, data),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MapScreen(filteredFilters: filters))),
        label: const Text('View Map'),
        icon: const Icon(Icons.map),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildFilterDropdown(String label, String type, List<String> options) {
    String? currentValue = type == 'city' ? filters.city : (type == 'cuisine' ? filters.cuisine : filters.tag);
    List<String?> finalOptions = [null, ...options];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: currentValue != null ? Colors.blue[100] : Colors.grey[200], borderRadius: BorderRadius.circular(20)),
      child: DropdownButton<String?>(
        hint: Text(label),
        value: currentValue,
        underline: const SizedBox(),
        items: finalOptions.map((v) => DropdownMenuItem(value: v, child: Text(v ?? 'All ($label)'))).toList(),
        onChanged: (val) => _updateFilter(type, val),
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
        stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          Set<Marker> markers = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            bool matchCity = filteredFilters.city == null || (data['address'] ?? '').toString().toLowerCase().contains(filteredFilters.city!.toLowerCase());
            bool matchCuisine = filteredFilters.cuisine == null || (data['cuisine'] ?? '').toString().toLowerCase() == filteredFilters.cuisine!.toLowerCase();
            bool matchTag = filteredFilters.tag == null || (data['recommendation_tags'] as List? ?? []).any((t) => t.toString().toLowerCase() == filteredFilters.tag!.toLowerCase());
            return matchCity && matchCuisine && matchTag;
          }).map((doc) {
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
              // שם המסעדה - עכשיו הוא לחיץ!
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
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.open_in_new, size: 16, color: Colors.blue.shade900),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // תגית מחיר
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: getPriceColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: getPriceColor()),
                    ),
                    child: Text(
                      priceLevel == 'not-known' ? "? Price" : priceLevel.toUpperCase(),
                      style: TextStyle(color: getPriceColor(), fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Essence - תיאור מאוזן
              if (data['recommendation_essence'] != null)
                Text(
                  data['recommendation_essence'],
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.4),
                ),

              const SizedBox(height: 16),

              // בלוק סנטימנט מהקהילה
              if (data['community_sentiment'] != null && data['community_sentiment'].toString().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
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
                      Text(
                        data['community_sentiment'],
                        style: TextStyle(color: Colors.blue.shade900, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // מנות מומלצות
              if ((data['must_order_dishes'] as List? ?? []).isNotEmpty) ...[
                const Text("Top Picks", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: (data['must_order_dishes'] as List).map((dish) => Chip(
                    label: Text(dish.toString(), style: const TextStyle(fontSize: 11)),
                    backgroundColor: Colors.orange.shade50,
                    side: BorderSide(color: Colors.orange.shade100),
                    visualDensity: VisualDensity.compact,
                  )).toList(),
                ),
                const SizedBox(height: 16),
              ],

              const Divider(),
              const SizedBox(height: 8),
              _buildActionButton(Icons.directions, 'Get Directions', Colors.blue, () async {
                 final loc = data['location'];
                 final url = "https://www.google.com/maps/dir/?api=1&destination=${loc['lat']},${loc['lng']}";
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

// פונקציית עזר לכפתורים כדי למנוע כפל קוד
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
    setState(() => _isSending = true);
    await FirebaseFirestore.instance.collection('tiktok_links').add({
      'url': _controller.text.trim(),
      'status': 'pending',
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