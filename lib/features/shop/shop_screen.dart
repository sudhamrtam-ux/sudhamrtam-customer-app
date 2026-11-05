import 'package:flutter/material.dart';

import 'product_details_screen.dart';
import '../../models/product_catalog.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  static const _products = ProductCatalog.products;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF82B440);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Our Products',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Discover pure dairy and naturally crafted farm products.',
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _products.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              final product = _products[index];

              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProductDetailsScreen(
                        productName: product.name,
                        category: product.category,
                        productIcon: product.icon,
                        description: product.description,
                        unit: product.unit,
                        price: product.price,
                      ),
                    ),
                  );
                },
                child: Card(
                  color: const Color(0xFFF5F8F0),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFE1EBCF)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(product.icon, size: 42, color: green),
                        const SizedBox(height: 14),
                        Text(
                          product.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          product.category,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'Pure • Natural • Traditional',
              style: TextStyle(color: green, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
