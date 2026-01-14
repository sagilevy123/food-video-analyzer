import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddLinkScreen extends StatefulWidget {
  const AddLinkScreen({super.key});
  @override
  State<AddLinkScreen> createState() => _AddLinkScreenState();
}

class _AddLinkScreenState extends State<AddLinkScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _otherCuisineController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isSending = false;
  String _selectedCuisine = 'Burger';
  String _selectedPrice = 'Unknown';

  final List<String> _cuisineOptions = ['Burger', 'Pizza', 'Cafe', 'Asian', 'Other'];
  final List<String> _priceOptions = ['Cheap', 'Normal', 'Expensive', 'Unknown'];

  int _mapPriceToLevel(String price) {
    switch (price) {
      case 'Cheap': return 1;
      case 'Normal': return 2;
      case 'Expensive': return 3;
      default: return 0;
    }
  }

  void _handleSave() async {
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();
    final city = _cityController.text.trim();

    if (url.isEmpty && (name.isEmpty || city.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a link or fill name and city")),
      );
      return;
    }

    setState(() => _isSending = true);

    if (url.isNotEmpty) {
      await FirebaseFirestore.instance.collection('tiktok_links').add({
        'url': url,
        'status': 'pending',
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      final finalCuisine = _selectedCuisine == 'Other' ? _otherCuisineController.text.trim() : _selectedCuisine;

      // We send to a temporary collection so the Server can Geocode the address properly
      await FirebaseFirestore.instance.collection('manual_restaurants').add({
        'name': name,
        'city': city,
        'manualAddress': _addressController.text.trim(),
        'cuisine': finalCuisine,
        'price_level': _mapPriceToLevel(_selectedPrice),
        'user_notes': _notesController.text.trim(),
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending'
      });
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Restaurant')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Quick Add via Link", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'Paste TikTok/Instagram link here',
                prefixIcon: const Icon(Icons.link),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("OR ADD MANUALLY", style: TextStyle(color: Colors.grey, fontSize: 12))),
                  Expanded(child: Divider()),
                ],
              ),
            ),

            _buildLabel("Restaurant Name *"),
            _buildTextField(_nameController, "Name"),
            const SizedBox(height: 16),
            _buildLabel("City *"),
            _buildTextField(_cityController, "City"),
            const SizedBox(height: 16),
            _buildLabel("Street Address (Optional)"),
            _buildTextField(_addressController, "Street, number, etc."),
            const SizedBox(height: 16),
            _buildLabel("Cuisine Type *"),
            DropdownButtonFormField<String>(
              value: _selectedCuisine,
              items: _cuisineOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) => setState(() => _selectedCuisine = val!),
              decoration: _inputDecoration(),
            ),
            if (_selectedCuisine == 'Other') ...[
              const SizedBox(height: 8),
              _buildTextField(_otherCuisineController, "Specify cuisine"),
            ],
            const SizedBox(height: 16),
            _buildLabel("Price Range"),
            DropdownButtonFormField<String>(
              value: _selectedPrice,
              items: _priceOptions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (val) => setState(() => _selectedPrice = val!),
              decoration: _inputDecoration(),
            ),
            const SizedBox(height: 16),
            _buildLabel("Notes"),
            _buildTextField(_notesController, "Your review...", maxLines: 3),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: _isSending
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save Restaurant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
  );

  Widget _buildTextField(TextEditingController controller, String hint, {int maxLines = 1}) => TextField(
    controller: controller,
    maxLines: maxLines,
    decoration: _inputDecoration(hint: hint),
  );

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.grey[50],
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey[300]!)),
  );
}