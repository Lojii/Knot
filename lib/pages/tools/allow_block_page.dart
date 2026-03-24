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
      height: AppTheme.sizing.toolbarHeight,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: TabBar(
        tabs: [
          Tab(text: 'tab.allow_list'.tr),
          Tab(text: 'tab.block_list'.tr),
        ],
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelPadding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.lg),
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
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.spacing.lg,
            vertical: AppTheme.spacing.sm,
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
              SizedBox(width: AppTheme.spacing.sm),
              Expanded(
                child: Text(
                  isAllow
                      ? 'allow_block.allow_desc'.tr
                      : 'allow_block.block_desc'.tr,
                  style: TextStyle(
                    fontSize: AppTheme.fontSize.sm,
                    color: theme.hintColor,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showAddDialog(context),
                icon: const Icon(Icons.add, size: 14),
                label: Text('action.add'.tr),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing.sm,
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
                  isAllow ? 'empty.no_allow'.tr : 'empty.no_block'.tr,
                  style: TextStyle(
                    color: theme.hintColor,
                    fontSize: AppTheme.fontSize.md,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: EdgeInsets.symmetric(vertical: AppTheme.spacing.sm),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                return ListTile(
                  dense: true,
                  title: Text(
                    list[i],
                    style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.md),
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
        title: Text(isAllow ? 'allow_block.add_allow'.tr : 'allow_block.add_block'.tr),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.md),
            decoration: InputDecoration(
              hintText: '*.example.com',
              hintStyle: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: AppTheme.fontSize.sm,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius.sm),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppTheme.spacing.sm,
                vertical: AppTheme.spacing.sm,
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
            child: Text('action.cancel'.tr),
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
            child: Text('action.add'.tr),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }
}
