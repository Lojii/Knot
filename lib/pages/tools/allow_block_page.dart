import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tools_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_tab_bar.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/empty_state.dart';

/// Inline panel for managing domain Allow/Block lists.
class AllowBlockPanel extends StatefulWidget {
  const AllowBlockPanel({super.key});

  @override
  State<AllowBlockPanel> createState() => _AllowBlockPanelState();
}

class _AllowBlockPanelState extends State<AllowBlockPanel> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          height: AppTheme.sizing.toolbarHeight,
          padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.lg),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: AppTabBar(
            tabs: ['tab.allow_list'.tr, 'tab.block_list'.tr],
            activeIndex: _tabIndex,
            onChanged: (i) => setState(() => _tabIndex = i),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: const [
              _DomainListTab(isAllow: true),
              _DomainListTab(isAllow: false),
            ],
          ),
        ),
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
              AppButton(
                label: 'action.add'.tr,
                icon: Icons.add,
                variant: AppButtonVariant.primary,
                onPressed: () => _showAddDialog(context),
              ),
            ],
          ),
        ),
        // Domain list
        Expanded(
          child: Obx(() {
            final list = isAllow ? toolsCtrl.allowList : toolsCtrl.blockList;
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.filter_list,
                title: isAllow ? 'empty.no_allow'.tr : 'empty.no_block'.tr,
              );
            }
            return ListView.separated(
              padding: EdgeInsets.symmetric(vertical: AppTheme.spacing.sm),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
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
                    tooltip: 'action.delete'.tr,
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
          child: AppTextField(
            controller: controller,
            autofocus: true,
            style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.md),
            hintText: '*.example.com',
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
