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
      final String name = data['name'] ?? 'Restaurant';
      final String essence = data['recommendation_essence'] ?? '';
      final List<dynamic> tags = data['recommendation_tags'] ?? [];
      final String videoUrl = data['videoUrl'] ?? '';
      final String websiteUrl = data['website'] ?? '';

      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (essence.isNotEmpty) Text(essence, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: tags.map((t) => Chip(label: Text(t.toString()))).toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final loc = data['location'];
                  final url = "https://www.google.com/maps/search/?api=1&query=${loc['lat']},${loc['lng']}";
                  if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.directions),
                label: const Text('Navigate'),
              ),
            ),
            if (websiteUrl.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final Uri uri = Uri.parse(websiteUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.language),
              label: const Text('Visit Website'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                side: const BorderSide(color: Colors.blue),
              ),
            ),
          ),
        ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  if (videoUrl.isNotEmpty) await launchUrl(Uri.parse(videoUrl), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.play_circle_fill),
                label: const Text('Watch TikTok'),
              ),
            ),
          ],
        ),
      );
    },
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