import 'package:flutter/material.dart';

import 'leaser_manage_page.dart';
import 'leaser_review_page.dart';
import 'widgets/admin_ui.dart';

class LeaserAdminModulePage extends StatelessWidget {
  const LeaserAdminModulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const AdminModuleHeader(
            icon: Icons.handshake_outlined,
            title: 'Leasers',
            subtitle: 'Review applications and manage existing leasers',
          ),
          const Divider(height: 1),
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              tabAlignment: TabAlignment.start,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Applications'),
                Tab(text: 'Manage'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
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
