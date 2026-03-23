import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tools_controller.dart';
import '../../theme/app_theme.dart';

/// Inline panel for managing domain Allow/Block lists.
class AllowBlockPanel extends StatelessWidget {
  const AllowBlockPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _AllowBlockTabBar(),
          Expanded(child: _AllowBlockTabBody()),
        ],
      ),
    );
  }
}

class _AllowBlockTabBar extends StatelessWidget {
  const _AllowBlockTabBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: AppTheme.toolbarHeight,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: const TabBar(
        tabs: [
          Tab(text: 'Allow List'),
          Tab(text: 'Block List'),
        ],
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelPadding: EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
      ),
    );
  }
}

class _AllowBlockTabBody extends StatelessWidget {
  const _AllowBlockTabBody();

  @override
  Widget build(BuildContext context) {
    return const TabBarView(
      children: [
        _DomainListTab(isAllow: true),
        _DomainListTab(isAllow: false),
      ],
    );
  }
}

class _DomainListTab extends StatelessWidget {
  final bool isAllow;
  const _DomainListTab({required this.isAllow});

  @override
  Widget build(BuildContext context) {
    final toolsCtrl = Get.find<ToolsController>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Description + Add button
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingLG,
            vertical: AppTheme.spacingSM,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Icon(
                isAllow ? Icons.check_circle_outline : Icons.block,
                size: 16,
                color: theme.hintColor,
              ),
              const SizedBox(width: AppTheme.spacingSM),
              Expanded(
                child: Text(
                  isAllow
                      ? 'Allow List: only show traffic from these domains'
                      : 'Block List: hide traffic from these domains',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSM,
                    color: theme.hintColor,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showAddDialog(context),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSM,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Domain list
        Expanded(
          child: Obx(() {
            final list = isAllow ? toolsCtrl.allowList : toolsCtrl.blockList;
            if (list.isEmpty) {
              return Center(
                child: Text(
                  isAllow ? 'No allow list entries' : 'No block list entries',
                  style: TextStyle(
                    color: theme.hintColor,
                    fontSize: AppTheme.fontSizeMD,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSM),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                return ListTile(
                  dense: true,
                  title: Text(
                    list[i],
                    style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSizeMD),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: theme.hintColor,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      if (isAllow) {
                        toolsCtrl.removeFromAllowList(i);
                      } else {
                        toolsCtrl.removeFromBlockList(i);
                      }
                    },
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context) {
    final controller = TextEditingController();
    final toolsCtrl = Get.find<ToolsController>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAllow ? 'Add to Allow List' : 'Add to Block List'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSizeMD),
            decoration: InputDecoration(
              hintText: '*.example.com',
              hintStyle: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: AppTheme.fontSizeSM,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingSM,
                vertical: AppTheme.spacingSM,
              ),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                if (isAllow) {
                  toolsCtrl.addToAllowList(value.trim());
                } else {
                  toolsCtrl.addToBlockList(value.trim());
                }
                Navigator.pop(ctx);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                if (isAllow) {
                  toolsCtrl.addToAllowList(value);
                } else {
                  toolsCtrl.addToBlockList(value);
                }
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }
}
