import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 数据库损坏兜底页
///
/// 启动前的只读健康探测发现主库损坏时展示，替代主页面：
/// 避免白屏或崩溃，并让用户知道历史备份还在、数据没有丢。
class DatabaseErrorPage extends StatelessWidget {
  const DatabaseErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 88,
                height: 88,
                // AppColors.tint 是运行时方法，不能放进 const BoxDecoration
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.expense),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  size: 44,
                  color: AppColors.expense,
                ),
              ),
              const SizedBox(height: AppDimens.gapLg),
              const Text(
                '账本暂时无法打开',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '账本数据可能已损坏，但历史备份仍保存在手机中，数据并没有丢失。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              _tip(
                icon: Icons.refresh,
                text: '完全关闭应用后重新打开，会自动重试',
              ),
              _tip(
                icon: Icons.delete_outline,
                text: '若仍然失败，请勿卸载应用——卸载会删除手机里的历史备份',
              ),
              _tip(
                icon: Icons.mail_outline,
                text: '可通过官网或邮箱联系开发者反馈',
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimens.radiusCard,
                      ),
                    ),
                  ),
                  // 关闭进程，用户回到桌面重新打开即完成重试
                  onPressed: () => exit(0),
                  child: const Text('重新打开', style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// 单条引导提示
  Widget _tip({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
