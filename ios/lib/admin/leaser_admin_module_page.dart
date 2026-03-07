import 'package:flutter/material.dart';

import 'leaser_manage_page.dart';
import 'leaser_review_page.dart';

class LeaserAdminModulePage extends StatelessWidget {
  const LeaserAdminModulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: const [
          Material(
            child: TabBar(
              tabs: [
                Tab(text: 'Applications'),
                Tab(text: 'Manage'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                LeaserReviewPage(),
                LeaserManagePage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
