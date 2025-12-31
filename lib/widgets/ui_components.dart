import 'package:flutter/material.dart';

/// Helper to build a price tag with color coding (Green for cheap, Red for expensive).
Widget buildPriceTag(dynamic priceLevel) {
  int level = 0;
  if (priceLevel is int) level = priceLevel;
  else if (priceLevel is String) level = int.tryParse(priceLevel) ?? 0;

  if (level == 0) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_money, size: 14, color: Colors.grey),
          SizedBox(width: 2),
          Text("No Info", style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Color color = level <= 1 ? Colors.green : (level == 2 ? Colors.orange : Colors.red);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.attach_money, size: 14, color: color),
        Text('\$' * level, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    ),
  );
}

/// Builds a compact chip for secondary information or video highlights.
Widget buildSmallBlueChip(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.blue[50],
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.blue[100]!),
    ),
    child: Text(
      text,
      style: TextStyle(color: Colors.blue[800], fontSize: 11, fontWeight: FontWeight.w500),
    ),
  );
}

/// Builds a standard chip used for global summary highlights.
Widget buildBlueChip(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.blue[100]!)),
    child: Text(text, style: TextStyle(color: Colors.blue[800], fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

/// Animated dot indicator for the PageView in the details dialog.
Widget buildDotsIndicator(int count, PageController controller) {
  double currentPage = controller.hasClients ? (controller.page ?? 0) : 0;
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(count, (index) {
      bool isSelected = currentPage.round() == index;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        height: 8, width: isSelected ? 24 : 8,
        decoration: BoxDecoration(color: isSelected ? Colors.blueAccent : Colors.grey[300], borderRadius: BorderRadius.circular(4)),
      );
    }),
  );
}