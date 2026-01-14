import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

// ייבוא המודל והרכיבים (החלף my_food_app בשם הפרויקט שלך)
import 'package:my_food_app/models/FilterCriteria.dart';
import 'package:my_food_app/widgets/ui_components.dart';
import 'package:my_food_app/services/url_service.dart';

/// Displays the animated details dialog with a swipeable PageView for multiple reviews.
void showDetails(BuildContext context, Map<String, dynamic> data) {
  // תיקון: אם יש המלצות, נשתמש בהן. אם אין (הוספה ידנית), נשאיר רשימה ריקה
  // ולא נכניס את [data] כברירת מחדל כפי שהיה קודם
  List<dynamic> recommendations = data['recommendations'] ?? [];

  final String docId = data['docId'] ?? '';
  int localRating = data['user_rating'] ?? 0;
  final TextEditingController notesController = TextEditingController(text: data['user_notes'] ?? '');

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, anim1, anim2) => const SizedBox(),
    transitionBuilder: (context, anim1, anim2, child) {
      return Transform.scale(
        scale: Curves.easeInOutBack.transform(anim1.value),
        child: FadeTransition(
          opacity: anim1,
          child: buildDetailsContent(context, data, recommendations, docId, localRating, notesController),
        ),
      );
    },
  );
}

/// Handles the renaming of a restaurant and persists changes to Firestore.
void showEditNameDialog(BuildContext context, Map<String, dynamic> data, String docId, StateSetter setModalState) {
  final TextEditingController nameEditController = TextEditingController(text: data['name']);

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Edit restaurant's name"),
      content: TextField(controller: nameEditController, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ביטול")),
        ElevatedButton(
          onPressed: () async {
            final newName = nameEditController.text.trim();
            if (newName.isNotEmpty) {
              await FirebaseFirestore.instance.collection('restaurants').doc(docId).update({'name': newName});
              // Update the UI state inside the open dialog immediately.
              setModalState(() {
                data['name'] = newName;
              });
            }
            Navigator.pop(context);
          },
          child: const Text("שמור"),
        ),
      ],
    ),
  );
}

/// Constructs the main structure for the restaurant details PageView.
Widget buildDetailsContent(BuildContext context, Map<String, dynamic> data, List<dynamic> recommendations, String docId, int localRating, TextEditingController notesController) {
  final int pageCount = 1 + recommendations.length;
  // יצירת ה-Controller מחוץ ל-Builder כדי לשמור על הייחוס שלו
  final PageController pageController = PageController(viewportFraction: 0.96);

  return StatefulBuilder(
    builder: (context, setModalState) {
      return Center(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.82,
          width: MediaQuery.of(context).size.width * 0.95,
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  physics: pageCount <= 1 ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
                  controller: pageController,
                  itemCount: pageCount,
                  // הוספת ה-onPageChanged כדי לעדכן את הנקודות בזמן אמת
                  onPageChanged: (index) {
                    setModalState(() {});
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return buildMainSummaryPage(context, data, localRating, notesController, setModalState, docId);
                    }
                    final rec = recommendations[index - 1] as Map<String, dynamic>;
                    return buildReviewerCardContent(context, data, rec);
                  },
                ),
              ),
              if (pageCount > 1) ...[
                const SizedBox(height: 12),
                // פונקציית הנקודות תקבל את ה-State המעודכן בזכות ה-setModalState לעיל
                buildDotsIndicator(pageCount, pageController),
              ],
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    },
  );
}

/// Builds the first page of the details view containing AI global summary and user notes.
Widget buildMainSummaryPage(BuildContext context, Map<String, dynamic> data, int localRating, TextEditingController notesController, StateSetter setModalState, String docId) {
  final summary = data['global_summary'] as Map<String, dynamic>?;
  final List<dynamic> chips = summary?['decision_chips'] ?? [];
  final String cuisine = data['cuisine'] ?? 'Restaurant';
  final location = data['location'] as Map<String, dynamic>?;

  return Card(
    elevation: 20,
    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // חפש את ה-Row שמכיל את שם המסעדה ותגית המחיר
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded( // חובה להשתמש ב-Expanded כאן כדי למנוע את החריגה הצהובה
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onDoubleTap: () => showEditNameDialog(context, data, docId, setModalState),
                          child: Row(
                            children: [
                              Flexible( // מאפשר לשם ארוך לרדת שורה או להצטמצם
                                child: Text(
                                  data['name'] ?? 'Restaurant',
                                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                                  overflow: TextOverflow.ellipsis, // מוסיף "..." אם השם ממש ארוך
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.edit_note, size: 22, color: Colors.grey[400]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            // עוטף גם את טקסט המטבח ב-Flexible במידת הצורך
                            Flexible(
                              child: Text(cuisine.toUpperCase(),
                                  style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.1),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 12),
                            buildPriceTag(data['price_level'] ?? summary?['price_level']),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // כפתור הניווט נשאר בצד ימין
                  if (location != null)
                    IconButton(
                      icon: const Icon(Icons.near_me, color: Colors.blue, size: 30),
                      onPressed: () => openMap(location['lat'], location['lng']),
                    ),
                ],
              ),

            const SizedBox(height: 12),
            Text(data['address'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13)),

            if (data['website'] != null && data['website'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final Uri url = Uri.parse(data['website']);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 6),
                    Text(
                      "Official Website",
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Divider(height: 40, thickness: 0.5),

            const Text("My Rating & Notes", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            // STAR RATING: Updates local state and Firebase synchronously.
            Row(
              children: List.generate(5, (i) => GestureDetector(
                onTap: () {
                  setModalState(() => localRating = i + 1);
                  FirebaseFirestore.instance.collection('restaurants').doc(docId).update({'user_rating': localRating});
                },
                child: Icon(i < localRating ? Icons.star : Icons.star_border,
                            color: Colors.amber, size: 28),
              )),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: "Add your personal notes...",
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (val) => FirebaseFirestore.instance.collection('restaurants').doc(docId).update({'user_notes': val}),
            ),

            const Divider(height: 40, thickness: 0.5),

            if (chips.isNotEmpty) ...[
              const Row(
                children: [
                  Icon(Icons.bolt, size: 16, color: Colors.amber),
                  SizedBox(width: 8),
                  Text("Quick Highlights",
                       style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: chips.map((tag) => buildBlueChip(tag.toString())).toList(),
              ),
            ],

            const SizedBox(height: 30),
            Center(
              child: Text("Swipe right for reviews",
                  style: TextStyle(color: Colors.grey[400], fontSize: 11)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Builds the card for individual video reviews, including the clickable thumbnail.
Widget buildReviewerCardContent(BuildContext context, Map<String, dynamic> data, Map<String, dynamic> rec) {
  final List<dynamic> highlights = rec['top_highlights'] ?? [];
  final bool isInstagram = rec['source'] == 'instagram';
  final String fullDescription = rec['full_description'] ?? 'No description available.';
  final String community = rec['community_sentiment'] ?? '';
  final String? videoUrl = rec['videoUrl'];
  const String hintText = "Tap a highlight to read the full review...";

  final String? thumbnailUrl = rec['thumbnailUrl'];
  String displayedText = hintText;

  return StatefulBuilder(
    builder: (context, setStateCard) {
      return Card(
        elevation: 20,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: Column(
            children: [
              // THUMBNAIL: Clickable area that redirects to the original video review.
              if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    if (videoUrl != null && videoUrl.isNotEmpty) {
                      launchURL(videoUrl);
                    }
                  },
                  child: Stack(
                    children: [
                      Image.network(
                        thumbnailUrl,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 180,
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(color: Colors.black.withOpacity(0.1)),
                      ),
                      const Positioned(
                        bottom: 12,
                        right: 12,
                        child: CircleAvatar(
                          backgroundColor: Colors.black54,
                          radius: 18,
                          child: Icon(Icons.play_arrow, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(height: 10, color: Colors.blue[100]),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(isInstagram ? Icons.camera_alt : Icons.music_note,
                                     size: 16, color: isInstagram ? Colors.purple : Colors.blue),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    rec['reviewerName'] ?? 'Expert',
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          buildPriceTag(data['price_level']),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // AI HIGHLIGHTS: Interactive chips that reveal the full review text on tap.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: highlights.map((h) => GestureDetector(
                          onTap: () {
                            setStateCard(() {
                              displayedText = (displayedText == fullDescription) ? hintText : fullDescription;
                            });
                          },
                          child: buildSmallBlueChip(h.toString()),
                        )).toList(),
                      ),

                      const SizedBox(height: 16),

                      if (community.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.blue[100]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // נקודת סנטימנט צבעונית
                                  buildSentimentDot(rec['sentiment_score']),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.forum_outlined, size: 14, color: Colors.blueGrey),
                                  const SizedBox(width: 4),
                                  const Text("Community Voice",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                community,
                                style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4)
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // REVIEW TEXT: Animated transition between hint text and full AI description.
                      Expanded(
                        child: SingleChildScrollView(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              displayedText,
                              key: ValueKey(displayedText),
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: displayedText == hintText ? Colors.grey : Colors.black87,
                                fontStyle: displayedText == hintText ? FontStyle.italic : FontStyle.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}